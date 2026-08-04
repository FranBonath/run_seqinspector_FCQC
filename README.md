# run_seqinspector_FCQC

This repository consists of bash scripts and dummy config files that can be used at NGI Stockholm to create a samplesheet for the nf-core/seqinspector pipeline based on a Illumina flowcell run directory.

Find the README for the individual scripts in this repo below:

1. [generate_seqinspector_samplesheet.sh](#1-generate_seqinspector_samplesheetsh)
2. [run_seqinspector_FCQC.sh](#2-run_seqinspector_fcqcsh)
3. [create_qc_symlinks.sh](#3-create_qc_symlinkssh)

## 1. generate_seqinspector_samplesheet.sh

### Overview

This script scans a sequencing output directory for paired-end FASTQ files and generates a CSV sample sheet. The script also includes the undetermined reads into the sample shee in that each lane of undetermined reads is added as a separate entry. Runs without undetermined files are taken into consideration. The output is printed to stdout and can be redirected to a file.

---

### Logic

1. **Input validation** — Expects exactly one argument (the base directory). Exits with usage info if not provided.

2. **FASTQ discovery** — Recursively searches `<base_directory>/Demultiplexing/` for all `*.fastq.gz` files (sorted).

3. **Flowcell ID extraction** — The flowcell ID is derived from the base directory name, which is expected to follow the Illumina naming convention `<date>_<machineID>_<run_number>_<flowcell_ID>`. The script takes the last `_`-delimited field as the flowcell ID (e.g. `20240101_M12345_0042_ABCDEFGH` → `ABCDEFGH`).

4. **Routing** — Each file is routed to one of two tracks:
   - **Undetermined**: filenames matching `[Uu]ndetermined*_L<lane>_R[12]_<number>.fastq.gz` (located directly in `Demultiplexing/`) are stored in separate lane-keyed arrays.
   - **Regular samples**: all other `*_R[12]_<number>.fastq.gz` files are stored by sample-name prefix.

5. **Pairing** — Both regular and undetermined files are paired into R1/R2 pairs using associative arrays keyed by sample prefix or lane, respectively.

6. **Sample sheet generation** — The script writes two groups of rows:

   **Regular samples** — for each unique sample key:
   - Extracts the **sample name** from the parent directory (stripping a leading `Sample_` prefix if present).
   - Extracts the **lane number** from the sample key (e.g. `SampleName_S1_L001` → `lane1`).
   - Composes the final sample name as `<sample_name>_<flowcell_ID>_lane<N>`.
   - Extracts the **batch name** from the grandparent directory (one level above the sample directory).

   **Undetermined reads** — for each lane that has undetermined files:
   - Sets `sample` to `undetermined_<flowcell_ID>_laneX` (where X is the lane number).
   - Sets `tags` to `undetermined`.

   All rows share the same columns:

   | Column    | Description                                                                        |
   |-----------|------------------------------------------------------------------------------------|
   | `sample`  | `<sample>_<flowcell_ID>_lane<N>`, or `undetermined_<flowcell_ID>_laneX`            |
   | `fastq_1` | Full path to the R1 FASTQ file                                                     |
   | `fastq_2` | Full path to the R2 FASTQ file                                                     |
   | `rundir`  | `<base_directory>` (the run directory, without the `Demultiplexing` subdirectory)  |
   | `tags`    | Batch name for regular samples; `undetermined` for undetermined reads              |

---

### Expected Directory Structure

```
<base_directory>/
└── Demultiplexing/
    ├── Undetermined_S0_L001_R1_001.fastq.gz   ← directly in Demultiplexing/
    ├── Undetermined_S0_L001_R2_001.fastq.gz
    ├── Undetermined_S0_L002_R1_001.fastq.gz   ← additional lanes (optional)
    ├── Undetermined_S0_L002_R2_001.fastq.gz
    └── <batch_name>/
        └── Sample_<sample_name>/
            ├── <sample_name>_R1_001.fastq.gz
            └── <sample_name>_R2_001.fastq.gz
```

---

### Usage

```bash
bash generate_samplesheet_with_undet.sh <base_directory>
```

#### Save to a file

```bash
bash generate_samplesheet_with_undet.sh /path/to/run > sample_sheet.csv
```

#### Example

```bash
bash generate_seqinspector_samplesheet.sh /path/to/outdir/seqinspector_outdir > sample_sheet.csv
```

This will produce a CSV like:

```
sample,fastq_1,fastq_2,rundir,tags
MySample_ABCDEFGH_lane1,/path/to/Demultiplexing/BatchA/Sample_MySample/MySample_R1_001.fastq.gz,/path/to/Demultiplexing/BatchA/Sample_MySample/MySample_R2_001.fastq.gz,/path/to/run,BatchA
undetermined_ABCDEFGH_lane1,/path/to/Demultiplexing/Undetermined_S0_L001_R1_001.fastq.gz,/path/to/Demultiplexing/Undetermined_S0_L001_R2_001.fastq.gz,/path/to/run,undetermined
undetermined_ABCDEFGH_lane2,/path/to/Demultiplexing/Undetermined_S0_L002_R1_001.fastq.gz,/path/to/Demultiplexing/Undetermined_S0_L002_R2_001.fastq.gz,/path/to/run,undetermined
```

---

### Notes

- The script uses `set -euo pipefail` — it will exit immediately on any error, unset variable, or failed pipe.
- If a sample is missing either R1 or R2, the corresponding field in the CSV will be empty (no error is raised).
- Both `Undetermined` and `undetermined` filename prefixes are recognised (case-insensitive match on the first letter).
- If no undetermined files are found, no undetermined rows are written — the script works correctly for runs without undetermined reads.
- Lanes are detected dynamically; any number of lanes (L001–L008) are supported.


## 2. run_seqinspector_FCQC.sh

Wrapper script that generates a sample sheet from a flowcell directory and launches the seqinspector QC pipeline. Supports a `--dry-run` flag to generate the sample sheet and print the fully resolved Nextflow command without executing it.

---

### Requirements

- `bash` 4.0+
- `nextflow` available on `$PATH`
- `generate_seqinspector_samplesheet.sh` present at the path defined in the script constants
- A filled-in `seqinspector_FCQC.config` file (see Configuration)

---

### Usage

```bash
bash run_seqinspector_FCQC.sh -c <config_file> -f <flowcell_path> [-o <samplesheet_outdir>] [--dry-run]
```

#### Options

| Flag | Required | Description |
|------|----------|-------------|
| `-c` | Yes | Path to the `seqinspector_FCQC.config` configuration file |
| `-f` | Yes | Path to the flowcell directory (e.g. `/path/to/[run_dir]`) |
| `-o` | No | Directory where the generated sample sheet will be saved. Defaults to `[DEFAULT output]` |
| `--dry-run` | No | Generate the sample sheet but print the Nextflow command instead of executing it |

#### Examples

```bash
# Minimal — use default samplesheet output directory
bash run_seqinspector_FCQC.sh \
    -c seqinspector_FCQC.config \
    -f /path/to/[run_dir]

# Custom samplesheet output directory
bash run_seqinspector_FCQC.sh \
    -c seqinspector_FCQC.config \
    -f /path/to/[run_dir] \
    -o /my/custom/samplesheets

# Dry run — generate samplesheet and print the Nextflow command without executing it
bash run_seqinspector_FCQC.sh \
    -c seqinspector_FCQC.config \
    -f /path/to/[run_dir] \
    --dry-run
```

---

### Configuration

The script reads pipeline paths from a config file that must be provided via `-c`. The config uses plain `KEY=VALUE` bash syntax:

```bash
# seqinspector_FCQC.config

NF_CONFIG="<path to nextflow infrastructure config>"
SEQINSPECTOR_CONFIG="<path to seqinspector pipeline config>"
OUTDIR="<path where pipeline output (MultiQC reports etc.) will be written>"
FASTQ_SCREEN_REFERENCES="<path to FastQ Screen reference list CSV>"

# Optional: directory for the Nextflow work/ directory (intermediate files)
#NF_WORKDIR="<path for the Nextflow work directory>"

# Optional: directory from which Nextflow is launched.
# .nextflow/ cache, logs and history are always written to the launch directory.
#NF_LAUNCHDIR="<directory from which nextflow run is executed>"
```

A dummy config file is provided as `seqinspector_FCQC.config`.

#### Config variable reference

| Variable | Required | Description |
|----------|----------|-------------|
| `NF_CONFIG` | Yes | Path to the Nextflow infrastructure config (executor, cluster settings) |
| `SEQINSPECTOR_CONFIG` | Yes | Path to the seqinspector pipeline config (tool parameters, references) |
| `OUTDIR` | Yes | Base directory for MultiQC reports and other pipeline output |
| `FASTQ_SCREEN_REFERENCES` | Yes | Path to the FastQ Screen reference list CSV |
| `NF_WORKDIR` | No | Directory for the Nextflow `work/` directory (intermediate files). If unset, Nextflow uses `./work` relative to the launch directory. Passed as `-w` to `nextflow run`. |
| `NF_LAUNCHDIR` | No | Directory from which Nextflow is launched. Nextflow always writes `.nextflow/` (cache, logs, history) into the launch directory. Set this to keep those files in a dedicated location. |

---

### Inputs

| Input | Source | Description |
|-------|--------|-------------|
| Flowcell directory | `-f` flag | Root directory of the sequencing run. Must contain a `Demultiplexing/` subdirectory with FASTQ files. |
| Config file | `-c` flag | Provides the four required pipeline path variables and up to two optional variables (`NF_WORKDIR`, `NF_LAUNCHDIR`) listed above. |
| Samplesheet output dir | `-o` flag (optional) | Directory where the generated CSV will be saved. |

---

### Outputs

| Output | Location | Description |
|--------|----------|-------------|
| Sample sheet CSV | `<samplesheet_outdir>/<flowcell_ID>_<YYYYMMDD>_<HHMMSS>.csv` | Generated by `generate_samplesheet_better_samplenames.sh`. Contains one row per sample and per lane of undetermined reads. |
| Pipeline output | `$OUTDIR/<flowcell_ID>_<YYYYMMDD>_<HHMMSS>/` | MultiQC reports and other seqinspector results written by Nextflow. `$OUTDIR` (from config) is the base directory; a timestamped subdirectory is created automatically. |

Both the samplesheet and the pipeline output directory share the same name, encoding the flowcell ID and the date/time of execution, for example:
```
ABCDEFGH_20240101_143022.csv          ← samplesheet
ABCDEFGH_20240101_143022/             ← pipeline output directory
```

---

### Logic

1. **Argument validation** — checks that `-c` and `-f` are provided; exits with usage message if not.

2. **Config loading** — sources the config file and verifies that all four required variables (`NF_CONFIG`, `SEQINSPECTOR_CONFIG`, `OUTDIR`, `FASTQ_SCREEN_REFERENCES`) are set and non-empty.

3. **Input validation** — confirms the flowcell directory exists; confirms the samplesheet generation script exists at its hardcoded path.

4. **Flowcell ID extraction** — takes the last `_`-delimited field of the flowcell directory name as the flowcell ID. This matches the Illumina run directory convention `<date>_<machineID>_<run_number>_<flowcell_ID>` (e.g. `20240101_M12345_0042_ABCDEFGH` → `ABCDEFGH`).

5. **Sample sheet generation** — runs `generate_seqinspector_samplesheet.sh` with the flowcell path. Output is first written to a temporary file; it is only moved to the final destination if the script exits successfully. This prevents a partial or empty CSV from being left behind on failure. After the output directory is created, its path is resolved to an absolute form so that it remains valid even if the process later changes directory (e.g. due to `NF_LAUNCHDIR`).

6. **Pipeline execution or dry run** — if `--dry-run` was passed, the fully resolved Nextflow command is printed to stdout and the pipeline is not executed. The sample sheet is still generated so the printed command references a real file path. Without `--dry-run`, seqinspector is launched via Nextflow. In both cases, the pipeline output directory is set to `$OUTDIR/<run_name>`, where `<run_name>` is the same `<flowcell_ID>_<YYYYMMDD>_<HHMMSS>` string used for the samplesheet filename. The fixed parameters (`--project`, `--igenomes_base`, `--skip_tools`) are hardcoded in the wrapper and are not user-configurable. If `NF_WORKDIR` is set, `-w "$NF_WORKDIR"` is appended to the Nextflow command to redirect intermediate files. If `NF_LAUNCHDIR` is set, the script changes into that directory before launching Nextflow (creating it if necessary), so that Nextflow's `.nextflow/` cache, logs, and history are written there rather than in the current working directory.

---

### Notes

- The script uses `set -euo pipefail` and will abort immediately on any error, unset variable, or failed pipe.
- Progress messages with timestamps are printed to stdout at each stage.
- `--dry-run` can be placed anywhere on the command line.


## 3. create_qc_symlinks.sh

Creates per-file symlinks of seqinspector QC results into the project analysis directories on the HPC, so that results are accessible for cross flowcell Multiqc reports from each project's dedicated analysis space without duplicating data.

### How it works

After a seqinspector run, this script reads the seqinspector samplesheet used in `run_seqinspector_FCQC.sh` to identify which projects were on the flowcell. The project ID (e.g. `P12345`) is extracted from the first `_`-delimited field of each sample name. The project name (the `tags` column in the samplesheet) is not used.

For each project ID, the script mirrors the relevant result subdirectories under the project's analysis path and symlinks individual files whose filename contains `<project_id>_` (anywhere in the name). Undetermined reads are always ignored.

The following seqinspector result subdirectories are processed (hard coded):
- `fastqc`
- `fastqscreen`

This means the following seqinspector output directories are ignored:
- `multiqc`
- `pipeline_info`
- `rundirparser`

The resulting structure looks like:

```
<analysis_base>/
└── P12345/
    └── qc_ngi/
        ├── fastqc/
        │   ├── sample_P12345_lane1_fastqc.html -> /path/to/results/fastqc/sample_P12345_lane1_fastqc.html
        │   └── sample_P12345_lane1_fastqc.zip  -> /path/to/results/fastqc/sample_P12345_lane1_fastqc.zip
        └── fastqscreen/
            └── sample_P12345_lane1_screen.txt  -> /path/to/results/fastqscreen/sample_P12345_lane1_screen.txt
```

### Usage

```bash
bash create_qc_symlinks.sh -b <analysis_base> -r <results_dir> [-s <samplesheet>] [-p <project_id> ...] [--dry-run]
```

Either `-s` or at least one `-p` must be provided (both can be used together).

## Options

| Flag | Required | Description |
|------|----------|-------------|
| `-b` | Yes | Base path for project analysis directories. Target path per project: `<analysis_base>/<project_id>/qc_ngi/<subdir>/`. |
| `-r` | Yes | Path to the seqinspector results directory for this run. |
| `-s` | Conditional | Path to the samplesheet CSV used for the run. Required if `-p` is not given. |
| `-p` | Conditional | Project ID to include (e.g. `P12345`). Repeat for multiple. Required if `-s` is not given. If used with `-s`, the specified IDs are validated against the samplesheet. |
| `--dry-run` | No | Print the actions that would be taken without creating any directories or symlinks. |

### Examples

**All projects on the flowcell (samplesheet required):**
```bash
bash create_qc_symlinks.sh \
  -b /project/ngi12345/keinbackup/NGI/ANALYSIS \
  -r /path/to/seqinspector/output/HXXX_20250130_143022 \
  -s /path/to/samplesheets/HXXX_20250130_143022.csv
```

**Specific project(s), validated against the samplesheet:**
```bash
bash create_qc_symlinks.sh \
  -b /project/ngi12345/keinbackup/NGI/ANALYSIS \
  -r /path/to/seqinspector/output/HXXX_20250130_143022 \
  -s /path/to/samplesheets/HXXX_20250130_143022.csv \
  -p P12345 -p P67890
```

**Specific project(s) without a samplesheet:**
```bash
bash create_qc_symlinks.sh \
  -b /project/ngi12345/keinbackup/NGI/ANALYSIS \
  -r /path/to/seqinspector/output/HXXX_20250130_143022 \
  -p P12345
```

**Dry run to check what would happen:**
```bash
bash create_qc_symlinks.sh \
  -b /project/ngi12345/keinbackup/NGI/ANALYSIS \
  -r /path/to/seqinspector/output/HXXX_20250130_143022 \
  -s /path/to/samplesheets/HXXX_20250130_143022.csv \
  --dry-run
```

### Notes

- The **project ID** is the first `_`-delimited field of the sample name (e.g. `P12345` from `P12345_101_HXXX_lane1`).
- Files are matched by the pattern `*<project_id>_*` — the project ID can appear anywhere in the filename and must be followed by an underscore.
- If a symlink already exists at the target path, it is skipped with a message rather than overwritten.
- If a path exists at the target location but is not a symlink (e.g. a real directory), it is skipped with a warning.
- If a result subdirectory (`fastqc`, `fastqscreen`) is not present in the results directory, it is skipped with a message.
- If no files matching `<project_id>_` are found in a subdirectory, a message is printed and no symlinks are created for that combination.
- If a project ID given with `-p` is not found in the samplesheet (when `-s` is also provided), a warning is printed and it is skipped. If none of the requested IDs are found, the script exits with an error.
- The samplesheet is expected to be in the CSV format produced by `generate_seqinspector_samplesheet.sh`, with columns: `sample, fastq_1, fastq_2, rundir, tags`.
