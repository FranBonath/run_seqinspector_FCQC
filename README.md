# run_seqinspector_FCQC

This repository consists of bash scripts and dummy config files that can be used at NGI Stockholm to create a samplesheet for the nf-core/seqinspector pipeline based on a Illumina flowcell run directory.

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
