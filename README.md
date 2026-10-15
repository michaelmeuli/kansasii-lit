# kansasii-lit

The workflow documentation and the scripts feeding downstream analyses have moved to
`/shares/sander.imm.uzh/MM/kansasii/repos/immensekansasii` (see `WORKFLOW.md` there).

What remains here are exploratory or one-off scripts in `scripts/`. They are not part of the project
run order (see `immensekansasii/WORKFLOW.md`, "Run order"); the numbers only give the order they build on each other:

| Script | Purpose |
|---|---|
| `01_lit_gtdb_226.sh`, `02_lit_gtdb_232.sh` | GTDB r226 / r232 metadata and kansasii-complex rows, type-strain look-ups in NCBI/ENA |
| `03_lit_gtdb_ref_check.sh` | compare the type-strain tables of r232 and r226 |
| `04_get_mkc_type_strains.sh` | reads/assemblies of the complex type strains from NCBI and ENA |
| `05_gtdb_adv_search_genomes.sh` | download genomes for the accession lists in `gtdb_adv_search_accessions/` |
| `lit_download.ps1` | PowerShell `scp` lines to fetch the tables to a Windows machine (not bash) |

## Windows checkout

- `.gitattributes` forces LF line endings, so a Windows checkout (even with
  `core.autocrlf=true`) keeps scripts runnable. Recommended: `git config core.autocrlf false`
  and `git config core.longpaths true`.
- Scripts default to the cluster root `/shares/sander.imm.uzh/MM/kansasii`; set the
  `KANSASII_ROOT` environment variable to point elsewhere (e.g. a mapped drive).
- Nextflow, Singularity and sbatch steps only run on the cluster (or WSL).

