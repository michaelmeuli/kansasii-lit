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
Needs the `datasets` CLI, available in the `env_immense` conda environment
(`conda activate env_immense`). Genomes already present in
`data/gtdb_genomes/Mycobacteriaceae/ncbi_dataset/data/` are skipped.

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

## Pipeline runs (immensekansasii)

Start every run of the immensekansasii (IMMense) pipeline in its own
subdirectory of `/shares/sander.imm.uzh/MM/kansasii/runs/`, not in `output/`.
Nextflow writes its `work/` directory into the directory the run is started
from. `work/` is large and only temporary, so it must not end up in
`output/`, which gets downloaded to local `kansasii_C`. Once a run has
finished and been checked, copy its end results to
`/shares/sander.imm.uzh/MM/kansasii/output/<run_name>/` and delete `work/`.

```bash
mkdir -p /shares/sander.imm.uzh/MM/kansasii/runs/<run_name>
cd /shares/sander.imm.uzh/MM/kansasii/runs/<run_name>
bash /shares/sander.imm.uzh/MM/kansasii/repos/immensekansasii/run_IMMENSE.sh -j <job_name> -t <input_type> -r <run_name> -i <input_dir>

# after the run: collect results (without work/) in output/
rsync -a --exclude work --exclude .nextflow /shares/sander.imm.uzh/MM/kansasii/runs/<run_name>/ /shares/sander.imm.uzh/MM/kansasii/output/<run_name>/
```

## Downloading results to local `kansasii_C`

Copy everything under `/shares/sander.imm.uzh/MM/kansasii/output/` to the
local `kansasii_C` folder from a local PowerShell terminal:

```powershell
New-Item -ItemType Directory -Path "$env:USERPROFILE\kansasii_C\downloads\" -Force
scp -r mimeul@cluster.s3it.uzh.ch:/shares/sander.imm.uzh/MM/kansasii/output/* "$env:USERPROFILE\kansasii_C\downloads\"
```
