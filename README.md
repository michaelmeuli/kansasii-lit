# kansasii-lit

Literature, GTDB and sample-mapping scripts for the *M. kansasii* project.
This README covers only the scripts whose outputs feed downstream analyses in
the other repos under `/shares/sander.imm.uzh/MM/kansasii/repos/`
(`immensekansasii`, `mlsa-kansasii`). The remaining scripts in `scripts/` are
exploratory or one-off.

Paths below are relative to `/shares/sander.imm.uzh/MM/kansasii/`.

## `scripts/gtdb_mycobacteria_genomes.sh`

Filters GTDB r232 metadata for Mycobacteriaceae, builds accession lists and
downloads all Mycobacteriaceae genomes with the NCBI `datasets` CLI. Run on
a compute node (`srun --pty -n 1 -c 6 --time=01:00:00 --mem=16G bash -l`).

```bash
bash scripts/gtdb_mycobacteria_genomes.sh
```

- Reads: `data/lit/gtdb/gtdb232/bac120_metadata_r232.tsv` (downloaded if missing)
- Writes to `output/lit/gtdb/gtdb232/`, among others:
  - `mycobacterium_relevant_species_representative_accessions_renamed.txt`:
    GTDB representatives of the kansasii complex, MTBC, MAC and *M. simiae*,
    paired with a `_query`-suffixed id so that GTDB-Tk does not reject them
    as duplicates of its reference genomes
  - `kansasii_complex_type_strains.tsv`, `mycobacterium_type_strains.tsv`
- Downloads genomes to `data/gtdb_genomes/Mycobacteriaceae/ncbi_dataset/data/`

Used downstream by:
- `immensekansasii/scripts/run.sh`: the relevant-species phylogeny
  (`kansasii_phylo.nf`) reads the renamed accession list and the genomes
- `mlsa-kansasii/scripts/link_gtdb_kansasii_complex.sh`: symlinks the
  downloaded kansasii-complex genomes by species

## `scripts/generate_itol_species_labels.sh`

Turns the `_query` tip labels of the `kansasii_phylo.nf` tree
(`kansasii_complex_tree.treefile`) into readable iTOL annotations. Run it
after `gtdb_mycobacteria_genomes.sh`.

```bash
bash scripts/generate_itol_species_labels.sh
```

- Reads: `data/lit/gtdb/gtdb232/bac120_metadata_r232.tsv`,
  `output/lit/gtdb/gtdb232/mycobacterium_relevant_species_representative_accessions_renamed.txt`
- Writes to `output/lit/gtdb/gtdb232/`:
  - `itol_species_labels.txt`: iTOL LABELS dataset (`Species name [accession]`)
  - `itol_species_colorstrip.txt`: iTOL DATASET_COLORSTRIP grouping tips into
    kansasii complex / MTBC / MAC / *M. simiae* complex

Upload the treefile to iTOL, then drag both files onto the tree.

## `scripts/screening_map_link.py`

Links project samples (TNR) to LNR, MHK (AST) and NGS numbers, using
`screening_map_project.csv` and `screening_map_strains.csv` as the sources of
truth. It then compares the result with the old `screening_map.csv` and prints
the differences.

```bash
conda activate kansasii_mic
python scripts/screening_map_link.py [--indir DIR] [--out FILE] [--copy-to DIR]
```

- Reads: `data/imm/` (default `--indir`)
- Writes: `data/imm/screening_map_link.csv`, and copies it to `output/mlsa/`
  (change with `--copy-to`)

Used downstream by `mlsa-kansasii` (`SCREENING_MAP` in `mlsa/__init__.py`,
`scripts/link_sanger_kansasii.sh`, `main2_sanger_differentiation/`), which
reads `data/imm/screening_map_link.csv`.

## Downloading results to local `kansasii_C`

Everything under `/shares/sander.imm.uzh/MM/kansasii/output/` can be copied to
the local `kansasii_C` folder with `scp` from a local PowerShell terminal
(see also `scripts/lit_download.sh`). Use `-r` for whole directories:

```powershell
# single file
scp mimeul@cluster.s3it.uzh.ch:/shares/sander.imm.uzh/MM/kansasii/output/mlsa/screening_map_link.csv "$env:USERPROFILE\kansasii_C\downloads\"

# whole directory
scp -r mimeul@cluster.s3it.uzh.ch:/shares/sander.imm.uzh/MM/kansasii/output/lit/gtdb/gtdb232 "$env:USERPROFILE\kansasii_C\downloads\"
```

The target folder must already exist. From a Linux/macOS shell, use
`~/kansasii_C/downloads/` as the destination instead.
