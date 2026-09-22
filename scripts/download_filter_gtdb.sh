#!/usr/bin/env bash
#
# Download the GTDB bac120 metadata/taxonomy release and filter it down to
# the M. kansasii species complex.
#
# Usage: download_filter_gtdb.sh [release]   (default release: 232)

set -euo pipefail

RELEASE="${1:-232}"

ROOT=/shares/sander.imm.uzh/MM/kansasii
DATA_DIR="$ROOT/data/lit/gtdb/gtdb$RELEASE"
OUT_DIR="$ROOT/output/lit/gtdb/gtdb$RELEASE"

mkdir -p "$DATA_DIR" "$OUT_DIR"
cd "$DATA_DIR"

for kind in metadata taxonomy; do
  tsv="bac120_${kind}_r${RELEASE}.tsv"
  if [ ! -f "$tsv" ]; then
    wget "https://data.gtdb.aau.ecogenomic.org/releases/release$RELEASE/$RELEASE.0/$tsv.gz"
    gunzip "$tsv.gz"
  fi
done

# --- filter GTDB metadata down to the M. kansasii species complex ------------

SPECIES_PATTERN='s__Mycobacterium (kansasii|persicum|pseudokansasii|innocens|attenuatum|ostraviense|gastri)'
METADATA="bac120_metadata_r${RELEASE}.tsv"
ACCESSIONS_OUT="$OUT_DIR/kansasii-complex-mlsa-accessions.txt"

# Column indices are looked up from the header at runtime so this stays
# robust to GTDB reordering columns between releases.
header=$(head -1 "$METADATA")
acc_col=$(echo "$header" | tr '\t' '\n' | grep -nx 'accession' | cut -d: -f1)
tax_col=$(echo "$header" | tr '\t' '\n' | grep -nx 'gtdb_taxonomy' | cut -d: -f1)

if [ -z "$acc_col" ] || [ -z "$tax_col" ]; then
  echo "ERROR: could not find 'accession' or 'gtdb_taxonomy' columns in $METADATA" >&2
  exit 1
fi

awk -F'\t' -v acc_col="$acc_col" -v tax_col="$tax_col" -v pattern="$SPECIES_PATTERN" '
  NR > 1 && $tax_col ~ pattern {
    acc = $acc_col
    sub(/^(RS_|GB_)/, "", acc)
    tax = $tax_col
    sub(/.*s__Mycobacterium /, "", tax)
    print acc "\t" tax
  }
' "$METADATA" | sort -u > "$ACCESSIONS_OUT"

n_acc=$(wc -l < "$ACCESSIONS_OUT")
echo "Wrote $n_acc kansasii-complex accessions to $ACCESSIONS_OUT"
echo "Per-species counts:"
cut -f2 "$ACCESSIONS_OUT" | sort | uniq -c
