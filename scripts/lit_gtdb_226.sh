#!/usr/bin/env bash

# srun --pty -n 1 -c 6 --time=01:00:00 --mem=16G bash -l

set -euo pipefail

DATA_DIR=/shares/sander.imm.uzh/MM/kansasii/data/lit/gtdb/gtdb226
OUT_DIR=/shares/sander.imm.uzh/MM/kansasii/output/lit/gtdb/gtdb226
mkdir -p "$DATA_DIR" "$OUT_DIR"

METADATA="$DATA_DIR/bac120_metadata_r226.tsv"
TAXONOMY="$DATA_DIR/bac120_taxonomy_r226.tsv"

# idempotent: skip download/decompress if already present, so re-running
# this script non-interactively doesn't hit gunzip's "overwrite? [y/N]"
# prompt (which would otherwise hang forever with no tty attached)
if [ ! -f "$METADATA" ]; then
  (cd "$DATA_DIR" && wget https://data.gtdb.aau.ecogenomic.org/releases/release226/226.0/bac120_metadata_r226.tsv.gz && gunzip bac120_metadata_r226.tsv.gz)
fi
if [ ! -f "$TAXONOMY" ]; then
  (cd "$DATA_DIR" && wget https://data.gtdb.aau.ecogenomic.org/releases/release226/226.0/bac120_taxonomy_r226.tsv.gz && gunzip bac120_taxonomy_r226.tsv.gz)
fi

cd "$OUT_DIR"

# the kansasii complex (MKC)
SPECIES_PATTERN='s__Mycobacterium (kansasii|persicum|pseudokansasii|innocens|attenuatum|ostraviense|gastri)'

grep -E "$SPECIES_PATTERN" "$METADATA" > kansasii_complex_rows_metadata.tsv
grep -E "$SPECIES_PATTERN" "$TAXONOMY" > kansasii_complex_rows_taxonomy.tsv


cut -f1 kansasii_complex_rows_metadata.tsv | sort > metadata_accessions.txt
cut -f1 kansasii_complex_rows_taxonomy.tsv | sort > taxonomy_accessions.txt
# informational sanity check only -- diff exits 1 when the files differ,
# which must not abort the rest of the script under set -e
diff metadata_accessions.txt taxonomy_accessions.txt || true


# filter kansasii_complex_rows_metadata.tsv for type-strain genomes.
# Prefer GTDB's own curation (gtdb_type_designation_ncbi_taxa == "type
# strain of species"); fall back to NCBI's own designation
# (ncbi_type_material_designation == "assembly from type material") for
# species GTDB hasn't confirmed yet -- e.g. M. ostraviense in r226 has no
# GTDB-confirmed type strain, only an NCBI-flagged one.
GTDBTYPE_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^gtdb_type_designation_ncbi_taxa$' | cut -d: -f1)
NCBITYPE_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^ncbi_type_material_designation$' | cut -d: -f1)

awk -F'\t' -v g="$GTDBTYPE_COL" -v n="$NCBITYPE_COL" '
$g == "type strain of species" || $n == "assembly from type material"
' kansasii_complex_rows_metadata.tsv > kansasii_complex_rows_metadata_type_strains.tsv


# extract assembly accession + biosample accession for type strains,
# then look up raw read run accessions on ENA via biosample

# locate the ncbi_biosample column dynamically (header comes from the full
# downloaded metadata file, since the filtered/type-strain files have no
# header row of their own) -- do NOT hardcode this, column order differs
# between GTDB releases
BIOSAMPLE_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^ncbi_biosample$' | cut -d: -f1)

cut -f1,"$BIOSAMPLE_COL" kansasii_complex_rows_metadata_type_strains.tsv > type_strains_accession_biosample.tsv


# type-strain genomes are typically older finished/reference assemblies
# submitted to NCBI without their own fastq raw reads, so a header-only /
# zero-row result here is unremarkable rather than a script bug.
echo -e "assembly_accession\tbiosample_accession\trun_accession\tfastq_ftp" > type_strains_ena_reads.tsv
while IFS=$'\t' read -r assembly biosample; do
  curl -s --retry 3 --retry-delay 2 "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${biosample}&result=read_run&fields=run_accession,fastq_ftp&format=tsv" \
    | tail -n +2 \
    | awk -F'\t' -v a="$assembly" -v b="$biosample" 'BEGIN{OFS="\t"} {print a, b, $1, $2}' \
    >> type_strains_ena_reads.tsv
done < type_strains_accession_biosample.tsv


# ---------------------------------------------------------------------
# final list: ENA assembly accession, biosample accession, species name
# ---------------------------------------------------------------------

# locate the remaining columns dynamically
TAX_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^gtdb_taxonomy$' | cut -d: -f1)
REPR_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^gtdb_genome_representative$' | cut -d: -f1)
ASSEMNAME_COL=$(head -1 "$METADATA" | tr '\t' '\n' | grep -n '^ncbi_assembly_name$' | cut -d: -f1)

# NB: use awk with field-index variables here, not `cut -f1,a,b,c,d` --
# cut always emits fields in ascending column-number order regardless of
# the order listed, so pulling several out-of-order columns that way
# silently mismatches which value lands in which position
awk -F'\t' -v bs="$BIOSAMPLE_COL" -v tx="$TAX_COL" -v rp="$REPR_COL" -v an="$ASSEMNAME_COL" 'BEGIN{OFS="\t"}
{
  accession = $1; biosample = $bs; repr = $rp; assembly_name = $an
  match($tx, /s__[^;]+/); species = substr($tx, RSTART+3, RLENGTH-3)
  is_repr = (accession == repr) ? 1 : 0
  print accession, biosample, species, is_repr, assembly_name
}' kansasii_complex_rows_metadata_type_strains.tsv > type_strains_candidates.tsv

# some species have more than one type-strain genome (e.g. M. kansasii has
# both a 2013 assembly and a 2024 resequencing of the same ATCC 12478
# culture, sharing one biosample) -- keep only the one GTDB has chosen as
# its species-cluster representative; species with a single type-strain
# genome are kept regardless of representative status
awk -F'\t' '
  NR==FNR { count[$3]++; next }
  count[$3] == 1 || $4 == 1
' type_strains_candidates.tsv type_strains_candidates.tsv \
  > type_strains_final_rows.tsv

# look up each kept row's ENA assembly accession+version via its biosample.
# a biosample can have more than one assembly attached (e.g. M. kansasii's
# biosample has both GCA_000157895.2 and GCA_040687845.1), so match ENA's
# assembly_name back against ncbi_assembly_name to pick the exact assembly
# this row refers to, rather than taking every hit under that biosample
echo -e "ena_accession\tbiosample_accession\tspecies" > type_strains_ena_biosample_species.tsv
while IFS=$'\t' read -r assembly biosample species is_repr assembly_name; do
  curl -s --retry 3 --retry-delay 2 "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${biosample}&result=assembly&fields=accession,version,assembly_name&format=tsv" \
    | tail -n +2 \
    | awk -F'\t' -v b="$biosample" -v s="$species" -v an="$assembly_name" 'BEGIN{OFS="\t"} $3==an {print $1"."$2, b, s}'
done < type_strains_final_rows.tsv | sort -u >> type_strains_ena_biosample_species.tsv


# ---------------------------------------------------------------------
# download the type-strain assemblies themselves via ENA (Browser API
# FASTA endpoint, which only serves INSDC/GenBank accessions, not RefSeq).
# NB: naively swapping RS_GCF_x.N -> GCA_x.N is NOT safe -- GCF_000157895.3
# has no GCA_000157895.3 (404). RefSeq and GenBank version numbers can
# drift apart, which is exactly why the ENA accession was resolved via the
# biosample+assembly_name lookup above rather than derived here.
#
# Uses the deduped ena_accession column from type_strains_ena_biosample_
# species.tsv, i.e. one FASTA per species -- not one per biosample -- so
# M. kansasii's two attached assemblies (2013 + 2024 resequencing) don't
# both get downloaded, only the GTDB-representative one does.
# ---------------------------------------------------------------------
REFDIR=/shares/sander.imm.uzh/MM/kansasii/data/reference_genomes_gtdb_226
mkdir -p "$REFDIR"

tail -n +2 type_strains_ena_biosample_species.tsv | cut -f1 | while read -r acc; do
  if ! wget -q -O "$REFDIR/${acc}.fasta" "https://www.ebi.ac.uk/ena/browser/api/fasta/${acc}?download=true"; then
    echo "WARNING: download failed for $acc" >&2
    rm -f "$REFDIR/${acc}.fasta"
    continue
  fi
  if [ ! -s "$REFDIR/${acc}.fasta" ]; then
    echo "WARNING: empty download for $acc" >&2
    rm -f "$REFDIR/${acc}.fasta"
  fi
done

