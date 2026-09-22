#!/usr/bin/env bash

# srun --pty -n 1 -c 6 --time=01:00:00 --mem=16G bash -l

set -euo pipefail

DATA_DIR=/shares/sander.imm.uzh/MM/kansasii/data/lit/gtdb/gtdb232
OUT_DIR=/shares/sander.imm.uzh/MM/kansasii/output/lit/gtdb/gtdb232
mkdir -p "$DATA_DIR" "$OUT_DIR"

METADATA="$DATA_DIR/bac120_metadata_r232.tsv"
if [ ! -f "$METADATA" ]; then
  (cd "$DATA_DIR" && wget https://data.gtdb.aau.ecogenomic.org/releases/release232/232.0/bac120_metadata_r232.tsv.gz && gunzip bac120_metadata_r232.tsv.gz)
fi

cd "$OUT_DIR"

# SPECIES_PATTERN='s__Mycobacterium (kansasii|persicum|pseudokansasii|innocens|attenuatum|ostraviense|gastri)'
# grep -E "$SPECIES_PATTERN" "$METADATA" > kansasii_complex_rows_metadata.tsv

MYCOBACTERIACEAE='f__Mycobacteriaceae'
(head -1 "$METADATA"; grep -F "$MYCOBACTERIACEAE" "$METADATA") > mycobacteriaceae_rows_metadata.tsv


ACCESSION=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^accession$' | cut -d: -f1)
REPR_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^gtdb_genome_representative$' | cut -d: -f1)
GTDB_REP_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^gtdb_representative$' | cut -d: -f1)   # t or f
TAX_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^gtdb_taxonomy$' | cut -d: -f1)
GTDBTYPE_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^gtdb_type_designation_ncbi_taxa$' | cut -d: -f1)
ASSEMNAME_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^ncbi_assembly_name$' | cut -d: -f1)
BIOSAMPLE_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^ncbi_biosample$' | cut -d: -f1)
NCBITYPE_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^ncbi_type_material_designation$' | cut -d: -f1)

# not used in pipeline
# for pipline filter by gtdb_representative (t/f) (and gtdb_taxonomy) and not by gtdb_type_designation_ncbi_taxa
# gtdb_type_designation_ncbi_taxa
# Mycobacterium kansasii shows up twice if you filter by gtdb_type_designation_ncbi_taxa = type strain of species, 
# because GTDB has two accessions from the same ncbi_biosample. 
# gtdb_representative = t picks one of them.
awk -F'\t' -v OFS='\t' \
  -v acc="$ACCESSION" -v repr="$REPR_COL" -v gtdbrep="$GTDB_REP_COL" \
  -v tax="$TAX_COL" -v gtype="$GTDBTYPE_COL" -v an="$ASSEMNAME_COL" \
  -v bs="$BIOSAMPLE_COL" -v ntype="$NCBITYPE_COL" \
  '{print $acc, $repr, $gtdbrep, $tax, $gtype, $an, $bs, $ntype}' \
  mycobacteriaceae_rows_metadata.tsv > mycobacteriaceae_selected_columns.tsv

# gtdb_type_designation_ncbi_taxa is the 5th column in mycobacteriaceae_selected_columns.tsv
# (position fixed by the print order above, unrelated to GTDBTYPE_COL which
# indexes the original bac120_metadata_r232.tsv)
GTYPE_SEL_COL=5
awk -F'\t' -v OFS='\t' -v gtype="$GTYPE_SEL_COL" 'NR==1 || $gtype=="type strain of species"' \
  mycobacteriaceae_selected_columns.tsv > mycobacteriaceae_type_strains.tsv

# Filter selected-columns table the same way as mycobacterium_representative_accessions.txt
# below (tax ~ g__Mycobacterium && gtdb_representative == "t"), not by
# gtdb_type_designation_ncbi_taxa, adjusted for the column positions in
# mycobacteriaceae_selected_columns.tsv (tax=4, gtdbrep=3).
MYCOBACTERIUM_PATTERN='g__Mycobacterium'
TAX_SEL_COL=4
GTDBREP_SEL_COL=3
awk -F'\t' -v OFS='\t' -v tax="$TAX_SEL_COL" -v gtdbrep="$GTDBREP_SEL_COL" -v pat="$MYCOBACTERIUM_PATTERN" \
  'NR==1 || ($tax ~ pat && $gtdbrep == "t")' \
  mycobacteriaceae_selected_columns.tsv > mycobacterium_type_strains.tsv

SPECIES_PATTERN='s__Mycobacterium (kansasii|persicum|pseudokansasii|innocens|attenuatum|ostraviense|gastri)'
(head -1 mycobacteriaceae_type_strains.tsv; grep -E "$SPECIES_PATTERN" mycobacteriaceae_type_strains.tsv) > kansasii_complex_type_strains.tsv


# Mycobacterium (genus-level, not just family) GTDB species-representative
# genomes, accession only, with the RS_/GB_ source-flag prefix stripped
# (e.g. RS_GCF_002102175.1 -> GCF_002102175.1). Not filtered on type-strain
# designation: GTDB picks the representative by assembly quality, so it's
# often a different (better) genome than the one NCBI flags as the type
# strain -- requiring both conditions at once returns an empty set.
MYCOBACTERIUM_PATTERN='g__Mycobacterium'
awk -F'\t' -v OFS='\t' \
  -v acc="$ACCESSION" -v tax="$TAX_COL" -v gtdbrep="$GTDB_REP_COL" \
  -v pat="$MYCOBACTERIUM_PATTERN" \
  '$tax ~ pat && $gtdbrep == "t" {print $acc}' \
  mycobacteriaceae_rows_metadata.tsv | cut -c4- > mycobacterium_representative_accessions.txt


# mycobacterium_representative_accessions.txt above is every Mycobacterium
# representative genome (850+ in r232) -- too verbose to work with directly.
# Narrow it down to representative genomes of well-known/clinically relevant
# species: the kansasii complex, M. tuberculosis complex (GTDB clusters
# bovis, bovis BCG, africanum, canettii, orygis, microti, caprae and
# pinnipedii into the single species s__Mycobacterium tuberculosis, so no
# separate terms are needed for them), the M. avium complex (avium,
# intracellulare -- which also absorbs M. chimaera strains in GTDB --
# colombiense, arosiense, marseillense, vulneris, including their GTDB
# _A/_B/_C suffixed subclusters), and simiae (incl. simiae_A).
RELEVANT_SPECIES_PATTERN='s__Mycobacterium (kansasii|persicum|pseudokansasii|innocens|attenuatum|ostraviense|gastri|tuberculosis|avium|intracellulare|colombiense|arosiense|marseillense|vulneris|simiae)'
awk -F'\t' -v OFS='\t' \
  -v acc="$ACCESSION" -v tax="$TAX_COL" -v gtdbrep="$GTDB_REP_COL" \
  -v pat="$RELEVANT_SPECIES_PATTERN" \
  '$tax ~ pat && $gtdbrep == "t" {print $acc}' \
  mycobacteriaceae_rows_metadata.tsv | cut -c4- > mycobacterium_relevant_species_representative_accessions.txt


# Every accession above is itself a GTDB-Tk reference genome (they were
# selected from bac120_metadata_r232.tsv, which is GTDB-Tk's own reference
# metadata), so feeding them to gtdbtk_classify_wf as query genomes fails
# outright: "You have N genomes with the same id as GTDB-Tk reference
# genomes, please rename them." Pair each accession with a renamed id
# (suffixed "_query") that run.sh uses as the destination filename when
# symlinking genomes into the pipeline input directory -- the original
# accession is kept in column 1 to still locate the source .fna/.fasta under
# GENOME_DATA_DIR.
awk -F'\t' -v OFS='\t' '{print $1, $1"_query"}' \
  mycobacterium_relevant_species_representative_accessions.txt > mycobacterium_relevant_species_representative_accessions_renamed.txt


OUTDIR="/shares/sander.imm.uzh/MM/kansasii/data/gtdb_genomes/Mycobacteriaceae"
CHUNK_SIZE=500
MAX_RETRIES=3


download_species() {
  local accfile="mycobacteriaceae_accessions.txt"
  local dest="$OUTDIR"
  local chunkdir="$dest/.accession_chunks"

  # GTDB accessions are prefixed with a 3-char source flag ("RS_"/"GB_")
  # that NCBI's `datasets` CLI doesn't accept -- strip it to get the bare
  # GCA_/GCF_ accession
  tail -n +2 mycobacteriaceae_rows_metadata.tsv | cut -f1 | cut -c4- > "$accfile"

  if [ ! -s "$accfile" ]; then
    echo "SKIP: no accessions found in mycobacteriaceae_rows_metadata.tsv" >&2
    return
  fi

  mkdir -p "$dest" "$chunkdir"
  echo "-- Mycobacteriaceae: downloading $(wc -l < "$accfile") accession(s) in chunks of $CHUNK_SIZE --"
  split -d -a 4 -l "$CHUNK_SIZE" "$accfile" "$chunkdir/chunk_"

  local chunk zip attempt ok
  for chunk in "$chunkdir"/chunk_*; do
    zip="$chunk.zip"
    ok=0
    for attempt in $(seq 1 "$MAX_RETRIES"); do
      echo "-- chunk $(basename "$chunk"): attempt $attempt/$MAX_RETRIES ($(wc -l < "$chunk") accession(s)) --"
      if datasets download genome accession --inputfile "$chunk" --include gff3,genome --filename "$zip" \
        && unzip -o -q "$zip" -d "$dest"; then
        ok=1
        break
      fi
      echo "chunk $(basename "$chunk") failed on attempt $attempt" >&2
      rm -f "$zip"
    done
    if [ "$ok" -ne 1 ]; then
      echo "ERROR: chunk $(basename "$chunk") failed after $MAX_RETRIES attempts" >&2
      return 1
    fi
    rm -f "$zip"
  done
}

download_species


