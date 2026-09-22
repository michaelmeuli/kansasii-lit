#!/usr/bin/env bash
#
# lit_gtdb_ref_check.sh
#
# Compares the type_strains_ena_biosample_species.tsv output produced by
# lit_gtdb_232.sh and lit_gtdb_226.sh, to check whether the two GTDB
# releases resolve the MKC type strains to the same ENA assembly
# accessions (i.e. whether re-running against a newer release changed
# which genome gets picked as any species' representative).

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <r232/type_strains_ena_biosample_species.tsv> <r226/type_strains_ena_biosample_species.tsv>" >&2
  exit 1
fi

R232="$1"
R226="$2"

for f in "$R232" "$R226"; do
  [ -f "$f" ] || { echo "ERROR: not found: $f" >&2; exit 1; }
done

echo "=== raw diff ($R232 vs $R226) ==="
if diff -u "$R232" "$R226"; then
  echo "IDENTICAL: both files match exactly, byte for byte."
  exit 0
fi

echo
echo "=== per-species comparison (ena_accession, biosample_accession) ==="

declare -A row232 row226

while IFS=$'\t' read -r acc bio sp; do
  [ "$acc" = "ena_accession" ] && continue
  row232["$sp"]="$acc"$'\t'"$bio"
done < "$R232"

while IFS=$'\t' read -r acc bio sp; do
  [ "$acc" = "ena_accession" ] && continue
  row226["$sp"]="$acc"$'\t'"$bio"
done < "$R226"

same=0
differ=0
only232=0
only226=0

while read -r sp; do
  [ -z "$sp" ] && continue
  v232="${row232[$sp]:-}"
  v226="${row226[$sp]:-}"
  if [ -z "$v232" ]; then
    printf 'ONLY IN r226  %-30s r226=[%s]\n' "$sp" "$v226"
    only226=$((only226 + 1))
  elif [ -z "$v226" ]; then
    printf 'ONLY IN r232  %-30s r232=[%s]\n' "$sp" "$v232"
    only232=$((only232 + 1))
  elif [ "$v232" = "$v226" ]; then
    printf 'SAME          %-30s %s\n' "$sp" "$v232"
    same=$((same + 1))
  else
    printf 'DIFFER        %-30s r232=[%s]  r226=[%s]\n' "$sp" "$v232" "$v226"
    differ=$((differ + 1))
  fi
done < <({ printf '%s\n' "${!row232[@]}"; printf '%s\n' "${!row226[@]}"; } | sort -u)

echo
echo "same=$same differ=$differ only_in_r232=$only232 only_in_r226=$only226"

[ "$differ" -eq 0 ] && [ "$only232" -eq 0 ] && [ "$only226" -eq 0 ]
