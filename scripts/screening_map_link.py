#!/usr/bin/env python
"""Build screening_map_link.csv: link project samples to LNR, MHK (AST) and NGS numbers.

Usage (conda activate kansasii_mic):
    python screening_map_link.py [--indir DIR] [--out FILE]

Sources of truth: screening_map_project.csv and screening_map_strains.csv (agree on TNR).
Links are made via
  - LNR (strains) == AUFTRAGSNUMMER (ast)
  - numbers hidden in BESCHREIBUNG (follow-up LNR2 / TNR, e.g. "Resi unter: 3386016 / tbm-2026311083")
  - DATEOFBIRTH as fallback (reopened cases get a new LNR/TNR)
Afterwards the result is compared with screening_map.csv.
"""
import argparse
import re
import sys
from pathlib import Path

import pandas as pd

TNR_RE = re.compile(r"(?<!\d)(20\d{8})(?!\d)")
LNR_RE = re.compile(r"(?<!\d)(\d{7,8})(?!\d)")


def warn(msg):
    print(f"WARNING: {msg}", file=sys.stderr)


def read(path, encoding="utf-8"):
    df = pd.read_csv(path, dtype=str, encoding=encoding, keep_default_na=False)
    df.columns = [c.strip() for c in df.columns]
    return df.drop(columns=[c for c in df.columns if c == "" or c.startswith("Unnamed")])


def load(indir):
    project = read(indir / "screening_map_project.csv")
    project = project[project["NR"] != ""].reset_index(drop=True)
    strains = read(indir / "screening_map_strains.csv", encoding="latin-1")
    ast = read(indir / "screening_map_ast.csv").drop_duplicates().reset_index(drop=True)
    ngs = read(indir / "screening_map_ngs_jc.csv").drop_duplicates().reset_index(drop=True)
    old = read(indir / "screening_map.csv")

    assert strains["TNR"].is_unique, "TNR not unique in strains"
    missing = set(project["TNR"]) - set(strains["TNR"]) - {""}
    assert not missing, f"project TNR missing in strains: {missing}"
    return project, strains, ast, ngs, old


def parse_beschreibung(text, lnr):
    """Return (follow-up TNRs, LNR2 candidates) found in BESCHREIBUNG."""
    tnrs = TNR_RE.findall(text)
    lnrs = [n for n in LNR_RE.findall(text) if n != lnr]
    return tnrs, lnrs


def find_mhk(tnr, s, ast):
    """Pick the AST TNR (MHK) for a project TNR by priority tiers; return (MHK, AST row) or (None, None)."""
    besch_tnrs, besch_lnrs = parse_beschreibung(s["BESCHREIBUNG"], s["LNR"])
    other = ast["TNR"] != tnr
    tiers = [
        ("BESCHREIBUNG TNR", ast["TNR"].isin(besch_tnrs)),
        ("LNR2", ast["AUFTRAGSNUMMER"].isin(besch_lnrs)),
        ("LNR", (ast["AUFTRAGSNUMMER"] == s["LNR"]) & other),
        ("DOB+date", (ast["DATEOFBIRTH"] == s["DATEOFBIRTH"]) & (s["DATEOFBIRTH"] != "")
         & (ast["EINGANGSDATUM"] == s["EINGANGSDATUM"]) & other),
        ("self", ~other),
    ]
    for name, mask in tiers:
        hits = ast[mask].sort_values("TNR")
        if hits.empty:
            continue
        if hits["TNR"].nunique() > 1:
            warn(f"TNR {tnr}: several MHK candidates via {name}: {sorted(hits['TNR'].unique())}; "
                 f"using {hits.iloc[0]['TNR']}")
        return hits.iloc[0]["TNR"], hits.iloc[0]
    if besch_tnrs:
        warn(f"TNR {tnr}: BESCHREIBUNG mentions {besch_tnrs} but none found in ast")
    return None, None


def build(project, strains, ast, ngs):
    S = strains.set_index("TNR")
    rows = []
    for _, p in project.iterrows():
        r = {"NR": p["NR"], "PROBENNUMMER": p["PROBENNUMMER"], "LNR": "", "LNR2": "",
             "TNR": p["TNR"], "TNR_NGS": "", "extra": [], "NGS": "", "MHK": "", "LABEL": p["LABEL"]}
        if p["TNR"]:
            s = S.loc[p["TNR"]]
            s = s.copy()
            s["TNR"] = p["TNR"]
            r["LNR"] = s["LNR"]
            mhk, arow = find_mhk(p["TNR"], s, ast)
            if mhk:
                r["MHK"] = mhk
            if arow is not None and arow["AUFTRAGSNUMMER"] != s["LNR"]:
                r["LNR2"] = arow["AUFTRAGSNUMMER"]
            else:
                _, besch_lnrs = parse_beschreibung(s["BESCHREIBUNG"], s["LNR"])
                if besch_lnrs:
                    r["LNR2"] = besch_lnrs[0]
        rows.append(r)

    by_tnr = {r["TNR"]: r for r in rows if r["TNR"]}
    for _, n in ngs.iterrows():
        t, nt = n["TNR"], n["NGS TNR"]
        if t in by_tnr:
            target = by_tnr[t]
        else:
            # NGS TNR not in project: resolve via DATEOFBIRTH in strains
            if t not in S.index or not S.loc[t, "DATEOFBIRTH"]:
                warn(f"NGS TNR {t} ({nt}): not in project and no DATEOFBIRTH in strains; unresolved")
                continue
            dob = S.loc[t, "DATEOFBIRTH"]
            cands = strains.loc[strains["DATEOFBIRTH"] == dob, "TNR"].tolist()
            hits = [c for c in cands if c in by_tnr]
            if len(hits) != 1:
                warn(f"NGS TNR {t} ({nt}): DOB {dob} gives project TNR {hits}; unresolved")
                continue
            target = by_tnr[hits[0]]
            target["TNR_NGS"] = t
            target["extra"] = [c for c in cands if c not in (t, hits[0])]
        if target["NGS"] and target["NGS"] != nt:
            warn(f"TNR {target['TNR']}: NGS conflict {target['NGS']} vs {nt}")
        target["NGS"] = nt

    n_extra = max(1, max(len(r["extra"]) for r in rows))
    extra_cols = [f"TNR{i + 3}" for i in range(n_extra)]
    for r in rows:
        extra = r.pop("extra")
        for i, c in enumerate(extra_cols):
            r[c] = extra[i] if i < len(extra) else ""
    cols = ["NR", "PROBENNUMMER", "LNR", "LNR2", "TNR", "TNR_NGS", *extra_cols, "NGS", "MHK", "LABEL"]
    return pd.DataFrame(rows)[cols]


def compare(link, old):
    print("\n=== Comparison with screening_map.csv ===")
    m = old.merge(link, on="NR", how="outer", suffixes=("_old", ""), indicator=True)
    only = m[m["_merge"] != "both"]
    print(f"rows: old {len(old)}, new {len(link)}, unmatched NR: {len(only)}")
    for col in ["PROBENNUMMER", "TNR", "LABEL"]:
        diff = m[(m["_merge"] == "both") & (m[f"{col}_old"] != m[col])]
        print(f"{col}: {'identical' if diff.empty else f'{len(diff)} differences'}")
        if not diff.empty:
            print(diff[["NR", f"{col}_old", col]].to_string(index=False))
    for col in ["MHK", "NGS"]:
        both = m[m["_merge"] == "both"]
        conflict = both[(both[f"{col}_old"] != "") & (both[f"{col}_old"] != both[col])]
        added = both[(both[f"{col}_old"] == "") & (both[col] != "")]
        print(f"{col}: old non-empty {(both[f'{col}_old'] != '').sum()}, new non-empty {(both[col] != '').sum()}, "
              f"conflicts/lost {len(conflict)}, added {len(added)}")
        if not conflict.empty:
            print(conflict[["NR", "TNR", f"{col}_old", col]].to_string(index=False))
        if not added.empty:
            print(added[["NR", "TNR", col]].to_string(index=False))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--indir", type=Path, default=Path("/shares/sander.imm.uzh/MM/kansasii/data/imm"))
    ap.add_argument("--out", type=Path, default=None, help="default: <indir>/screening_map_link.csv")
    args = ap.parse_args()
    out = args.out or args.indir / "screening_map_link.csv"

    project, strains, ast, ngs, old = load(args.indir)
    link = build(project, strains, ast, ngs)
    link.to_csv(out, index=False)
    print(f"wrote {out} ({len(link)} rows)")
    compare(link, old)


if __name__ == "__main__":
    main()
