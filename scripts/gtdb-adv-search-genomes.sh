#!/usr/bin/env bash
#
# gtdb-adv-search-genomes.sh
#
# Batch-download genome assemblies (+ GFF3 annotation) for species in the
# Mycobacterium kansasii complex (MKC), using accession lists exported from
# the GTDB advanced search (https://gtdb.ecogenomic.org/advanced).
#
# One `datasets` call per species (not per accession) via --inputfile, so a
# 12-genome species is a single zip instead of 12 separate downloads.
#
# Usage:
#   ./gtdb-adv-search-genomes.sh                 # every species with an accession list
#   ./gtdb-adv-search-genomes.sh persicum gastri  # just the species named
#
# Add a new species by dropping scripts/gtdb_adv_search_accessions/<short>-accessions.txt
# (one accession per line) and adding <short> to SPECIES_NAME below -- no
# other script changes needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCESSIONS_DIR="$SCRIPT_DIR/gtdb_adv_search_accessions"
# species_key subdir naming matches params.kansasii_ref_dir / kansasii_snippy_db
# elsewhere in the pipeline (see modules/kansasii_phylo.nf)
OUTDIR="/shares/sander.imm.uzh/MM/kansasii/data/gtdb_genomes"

declare -A SPECIES_NAME=(
  ["kansasii"]="Mycobacterium_kansasii"
  ["persicum"]="Mycobacterium_persicum"
  ["pseudokansasii"]="Mycobacterium_pseudokansasii"
  ["innocens"]="Mycobacterium_innocens"
  ["attenuatum"]="Mycobacterium_attenuatum"
  ["ostraviense"]="Mycobacterium_ostraviense"
  ["gastri"]="Mycobacterium_gastri"
)

download_species() {
  local short="$1"
  local accfile="$ACCESSIONS_DIR/${short}-accessions.txt"
  local species_key="${SPECIES_NAME[$short]:?unknown species short name: $short (add it to SPECIES_NAME)}"
  local dest="$OUTDIR/$species_key"

  if [ ! -s "$accfile" ]; then
    echo "SKIP $short: no accession list at $accfile" >&2
    return
  fi

  mkdir -p "$dest"
  echo "-- $species_key: downloading $(wc -l < "$accfile") accession(s) --"
  datasets download genome accession --inputfile "$accfile" --include gff3,genome --filename "$dest/${short}.zip"
  unzip -o -q "$dest/${short}.zip" -d "$dest"
}

if [ "$#" -gt 0 ]; then
  for short in "$@"; do
    download_species "$short"
  done
else
  for accfile in "$ACCESSIONS_DIR"/*-accessions.txt; do
    [ -e "$accfile" ] || continue
    short="$(basename "$accfile" -accessions.txt)"
    download_species "$short"
  done
fi
