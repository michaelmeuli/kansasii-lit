#!/usr/bin/env bash
#
# get_mkc_type_strains.sh
#
# Find and download raw reads (and assemblies) for the type strains of the
# Mycobacterium kansasii complex (MKC):
#   M. kansasii s.s., M. persicum, M. pseudokansasii, M. innocens,
#   M. attenuatum, M. ostraviense, M. gastri
#
# Uses BOTH NCBI (EDirect + Datasets CLI) and ENA (Portal API) so you can
# cross-check and fall back if one source is missing/slow.
#
# REQUIREMENTS (install first):
#   conda install -c conda-forge -c bioconda entrez-direct ncbi-datasets-cli \
#       sra-tools fastq-dl jq curl
#
# NOTE ON THIS SCRIPT'S ORIGIN:
#   I (Claude) could not execute the live NCBI/ENA queries myself — my sandbox's
#   network egress is restricted to package-registry domains (pypi, npm, github,
#   etc.) and does not include eutils.ncbi.nlm.nih.gov / www.ebi.ac.uk. The
#   accessions hardcoded in KNOWN_TYPE_STRAINS below were pulled from LPSN,
#   BacDive, and the primary taxonomy papers (Shahraki et al. 2017, Tagini et
#   al. 2019, Kaščáková et al. 2021) via web search, and are real -- but you
#   should let the dynamic lookups in this script reconfirm/expand them, since
#   new SRA/ENA submissions get added over time.
#
set -euo pipefail

OUTDIR="./mkc_type_strains"
mkdir -p "$OUTDIR"/{metadata,reads,assemblies}

# ---------------------------------------------------------------------------
# 0. Species list + known type-strain anchors
#    (name -> "search terms to also try, since taxid reassignment lags")
# ---------------------------------------------------------------------------
#
# https://lpsn.dsmz.de/species/mycobacterium-kansasii
# https://lpsn.dsmz.de/species/mycobacterium-persicum
# https://lpsn.dsmz.de/species/mycobacterium-pseudokansasii
# https://lpsn.dsmz.de/species/mycobacterium-innocens
# https://lpsn.dsmz.de/species/mycobacterium-attenuatum
# https://lpsn.dsmz.de/species/mycobacterium-ostraviense
# https://lpsn.dsmz.de/species/mycobacterium-gastri
declare -A SPECIES=(
  ["Mycobacterium kansasii"]="ATCC 12478" # Type strain: ATCC 12478; CIP 104589; DSM 44162; JCM 6379; NCTC 13024
  ["Mycobacterium persicum"]="AFPC-000227" # Type strain: AFPC-000227; CIP 111197; DSM 104278
  ["Mycobacterium pseudokansasii"]="MK142" # Type strain: CCUG 72128; DSM 107152; MK142
  ["Mycobacterium innocens"]="MK13" # Type strain: CCUG 72126; DSM 107161; MK13
  ["Mycobacterium attenuatum"]="MK41" # Type strain: CCUG 72127; DSM 107153; MK41
  ["Mycobacterium ostraviense"]="241/15" # Nomenclatural type: 241/15T; DSM 110538; ITM 501146
  ["Mycobacterium gastri"]="DSM 43505" #ATCC 15754; CCUG 20995; CIP 104530; DSM 43505; JCM 12407#
)

# Known assembly accessions (verified via LPSN/BacDive/NCBI); used as a
# fallback anchor to fetch the correct BioSample even if the taxon-name
# search below returns nothing (common for these newly split species).
declare -A KNOWN_ASSEMBLY=(
  ["Mycobacterium kansasii"]="GCA_000157895.2"
  ["Mycobacterium persicum"]="GCF_002086675.1"
  ["Mycobacterium ostraviense"]="GCA_002705925.1"
  # pseudokansasii / innocens / attenuatum / gastri: only WGS prefixes are
  # confirmed from the literature (UPHU01, UPHQ01, UPHT01, LQOX01) -- resolve
  # the full GCA_* accession dynamically in step 1b.
)
declare -A KNOWN_WGS_PREFIX=(
  ["Mycobacterium pseudokansasii"]="UPHU01"
  ["Mycobacterium innocens"]="UPHQ01"
  ["Mycobacterium attenuatum"]="UPHT01"
  ["Mycobacterium gastri"]="LQOX01"
)

echo "=== Step 1: NCBI -- resolve type-strain assemblies + BioSamples ==="

for sp in "${!SPECIES[@]}"; do
  safe=$(echo "$sp" | tr ' ' '_')
  echo "-- $sp --"

  # 1a. Try the type_material filter via Datasets CLI (most reliable when it works)
  datasets summary genome taxon "$sp" --as-json-lines 2>/dev/null \
    | jq -c 'select(.type_material != null) |
             {accession, organism: .organism.organism_name,
              biosample: .assembly_info.biosample.accession,
              type_material: .type_material.type_label}' \
    > "$OUTDIR/metadata/${safe}_type_material.jsonl" || true

  # 1b. Fallback: if nothing came back (common -- taxid may not be re-tagged
  # yet, or type_material flag missing), use the known assembly/WGS anchor.
  if [[ ! -s "$OUTDIR/metadata/${safe}_type_material.jsonl" ]]; then
    if [[ -n "${KNOWN_ASSEMBLY[$sp]:-}" ]]; then
      acc="${KNOWN_ASSEMBLY[$sp]}"
      echo "  (using known anchor accession: $acc)"
      datasets summary genome accession "$acc" --as-json-lines \
        | jq -c '{accession, organism: .organism.organism_name,
                  biosample: .assembly_info.biosample.accession}' \
        > "$OUTDIR/metadata/${safe}_type_material.jsonl" || true
    elif [[ -n "${KNOWN_WGS_PREFIX[$sp]:-}" ]]; then
      wgs="${KNOWN_WGS_PREFIX[$sp]}"
      echo "  (resolving via WGS prefix $wgs through Nucleotide/Assembly link)"
      esearch -db nucleotide -query "${wgs}[Accession]" \
        | elink -target biosample \
        | esummary \
        | xtract -pattern DocumentSummarySet -element Accession \
        > "$OUTDIR/metadata/${safe}_biosample.txt" || true
    fi
  fi

  # 1c. From whichever BioSample we found, pull linked SRA runs
  biosample=$(jq -r '.biosample // empty' "$OUTDIR/metadata/${safe}_type_material.jsonl" 2>/dev/null | head -1)
  if [[ -z "$biosample" && -f "$OUTDIR/metadata/${safe}_biosample.txt" ]]; then
    biosample=$(head -1 "$OUTDIR/metadata/${safe}_biosample.txt")
  fi

  if [[ -n "$biosample" ]]; then
    echo "  BioSample: $biosample -> fetching linked SRA runs"
    esearch -db biosample -query "$biosample" \
      | elink -target sra \
      | efetch -format runinfo \
      > "$OUTDIR/metadata/${safe}_runinfo.csv" || true
  else
    echo "  !! No BioSample resolved for $sp -- try the strain-name fallback"
    echo "     search manually: esearch -db biosample -query \"${SPECIES[$sp]}[All Fields]\""
  fi
done

echo ""
echo "=== Step 2: ENA -- cross-check via Portal API (taxon name + strain synonym) ==="

for sp in "${!SPECIES[@]}"; do
  safe=$(echo "$sp" | tr ' ' '_')
  enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote('$sp'))")

  curl -s "https://www.ebi.ac.uk/ena/portal/api/search?result=read_run&query=tax_name(%22${enc}%22)&fields=run_accession,sample_accession,study_accession,scientific_name,strain,library_strategy,instrument_platform,fastq_ftp&format=tsv" \
    -o "$OUTDIR/metadata/${safe}_ena_runs.tsv" || true

  # Fallback: search by the strain designation itself (e.g. "MK142", "241/15"),
  # since ENA sample records often carry the strain name but not yet the new
  # species-level taxon.
  strain_enc=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${SPECIES[$sp]}'))")
  curl -s "https://www.ebi.ac.uk/ena/portal/api/search?result=read_run&query=strain=%22${strain_enc}%22&fields=run_accession,sample_accession,study_accession,scientific_name,strain,fastq_ftp&format=tsv" \
    -o "$OUTDIR/metadata/${safe}_ena_by_strain.tsv" || true

  rows=$(($(wc -l < "$OUTDIR/metadata/${safe}_ena_runs.tsv" 2>/dev/null || echo 1) - 1))
  echo "-- $sp: ${rows} run(s) found by taxon name on ENA (see *_ena_by_strain.tsv too)"
done

echo ""
echo "=== Step 3: Download raw reads for whatever runs were found ==="

for f in "$OUTDIR"/metadata/*_ena_runs.tsv "$OUTDIR"/metadata/*_ena_by_strain.tsv; do
  [[ -s "$f" ]] || continue
  awk -F'\t' 'NR>1 && $NF!="" {print $NF}' "$f" | tr ';' '\n' | while read -r url; do
    [[ -z "$url" ]] && continue
    wget -nc -q -P "$OUTDIR/reads" "ftp://${url}" &
  done
done
wait

# NCBI-side fallback download (prefer this only if ENA had nothing for a run)
for f in "$OUTDIR"/metadata/*_runinfo.csv; do
  [[ -s "$f" ]] || continue
  tail -n +2 "$f" | cut -d',' -f1 | while read -r run; do
    [[ -z "$run" ]] && continue
    echo "Fetching $run via SRA Toolkit..."
    prefetch "$run" -O "$OUTDIR/reads" \
      && fasterq-dump --split-files -O "$OUTDIR/reads" "$OUTDIR/reads/$run"
  done
done

echo ""
echo "=== Step 4 (optional): also grab the type-strain genome assemblies ==="
for sp in "${!KNOWN_ASSEMBLY[@]}"; do
  acc="${KNOWN_ASSEMBLY[$sp]}"
  datasets download genome accession "$acc" \
    --include genome \
    --filename "$OUTDIR/assemblies/${acc}.zip"
done

echo ""
echo "Done. Check $OUTDIR/metadata/*.tsv and *.csv for what was actually found --"
echo "for these recently-split species, expect gaps: not every type strain has"
echo "public raw reads (some depositions are assembly-only), and some records"
echo "may still be filed under the old 'Mycobacterium kansasii' taxid."
