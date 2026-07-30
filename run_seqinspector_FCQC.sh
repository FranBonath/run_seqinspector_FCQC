#!/usr/bin/env bash
# run_seqinspector_FCQC.sh
#
# Wrapper that generates a sample sheet from a flowcell directory and
# launches the seqinspector pipeline.
#
# Usage:
#   bash run_seqinspector_FCQC.sh -c <config_file> -f <flowcell_path> [-o <samplesheet_outdir>] [--dry-run]
#
# Options:
#   -c          Path to the seqinspector_FCQC.config file (required)
#   -f          Path to the flowcell directory (required)
#   -o          Directory where the generated sample sheet will be saved (optional)
#               Default: /proj/ngi2016003/nobackup/fran/analysis/seqinspector/production_wf_test/seqinspector_samplesheets
#   --dry-run   Generate the sample sheet but print the Nextflow command instead of executing it

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SAMPLESHEET_SCRIPT="[path to generate_seqinspector_samplesheet.sh]"

[[ ! -f "$SAMPLESHEET_SCRIPT" ]] && { echo "Error: samplesheet script not found: $SAMPLESHEET_SCRIPT"; exit 1; }

DEFAULT_SAMPLESHEET_OUTDIR="[path to default seqinspector samplesheet outdir]"


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 -c <config_file> -f <flowcell_path> [-o <samplesheet_outdir>] [--dry-run]"
    exit 1
}

config_file=""
flowcell_path=""
samplesheet_outdir=""
dry_run=false

# Extract --dry-run before passing remaining args to getopts
args=()
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        dry_run=true
    else
        args+=("$arg")
    fi
done
if (( ${#args[@]} > 0 )); then
    set -- "${args[@]}"
else
    set --
fi

while getopts ":c:f:o:" opt; do
    case $opt in
        c) config_file="$OPTARG" ;;
        f) flowcell_path="$OPTARG" ;;
        o) samplesheet_outdir="$OPTARG" ;;
        *) usage ;;
    esac
done

[[ -z "$config_file" ]]   && { echo "Error: -c <config_file> is required."; usage; }
[[ -z "$flowcell_path" ]] && { echo "Error: -f <flowcell_path> is required."; usage; }

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------

if [[ ! -f "$config_file" ]]; then
    echo "Error: config file not found: $config_file"
    exit 1
fi

# shellcheck source=/dev/null
source "$config_file"

# Verify required config variables are set
for var in NF_CONFIG SEQINSPECTOR_CONFIG OUTDIR FASTQ_SCREEN_REFERENCES SEQINSPECTOR_PIPELINE_ORG; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: '$var' is not set in $config_file"
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Resolve paths and names
# ---------------------------------------------------------------------------

flowcell_path="${flowcell_path%/}"

if [[ ! -d "$flowcell_path" ]]; then
    echo "Error: flowcell directory not found: $flowcell_path"
    exit 1
fi

# Extract flowcell ID (last '_'-delimited field of the directory name)
flowcell_id=$(basename "$flowcell_path")
flowcell_id="${flowcell_id##*_}"

# Apply default samplesheet output directory if not specified by user
samplesheet_outdir="${samplesheet_outdir:-$DEFAULT_SAMPLESHEET_OUTDIR}"

# Build samplesheet filename and output directory name: <flowcell_ID>_<YYYYMMDD>_<HHMMSS>
timestamp=$(date +"%Y%m%d_%H%M%S")
run_name="${flowcell_id}_${timestamp}"
samplesheet_name="${run_name}.csv"
samplesheet_path="${samplesheet_outdir}/${samplesheet_name}"
pipeline_outdir="${OUTDIR}/${run_name}"

# ---------------------------------------------------------------------------
# Generate sample sheet
# ---------------------------------------------------------------------------

echo "[$(date)] Generating sample sheet: $samplesheet_path"

mkdir -p "$samplesheet_outdir"
# Resolve to absolute path so it survives any later cd (e.g. into NF_LAUNCHDIR)
samplesheet_outdir="$(cd "$samplesheet_outdir" && pwd)"
samplesheet_path="${samplesheet_outdir}/${samplesheet_name}"

tmp=$(mktemp)
bash "$SAMPLESHEET_SCRIPT" "$flowcell_path" > "$tmp" && mv "$tmp" "$samplesheet_path"

echo "[$(date)] Sample sheet written to: $samplesheet_path"

# ---------------------------------------------------------------------------
# Run or dry-run seqinspector
# ---------------------------------------------------------------------------

nf_command=(
    nextflow run $SEQINSPECTOR_PIPELINE_ORG
    -profile uppmax
    -c "$NF_CONFIG"
    -c "$SEQINSPECTOR_CONFIG"
    --project ngi2016003
    --igenomes_base /sw/data/igenomes/
    --input "$samplesheet_path"
    --outdir "$pipeline_outdir"
    --fastq_screen_references "$FASTQ_SCREEN_REFERENCES"
    --skip_tools bwamem2_index,bwamem2_mem,picard_collectmultiplemetrics,samtools_faidx,samtools_index,seqfu_stats
)

[[ -n "${NF_WORKDIR:-}" ]] && nf_command+=(-w "$NF_WORKDIR")

if [[ "$dry_run" == true ]]; then
    echo ""
    echo "[$(date)] Dry run — seqinspector command that would be executed:"
    echo ""
    [[ -n "${NF_LAUNCHDIR:-}" ]] && printf 'cd "%s"\n\n' "$NF_LAUNCHDIR"
    printf 'nextflow run "%s" \\\n' "$SEQINSPECTOR_PIPELINE_ORG"
    printf '    -profile uppmax \\\n'
    printf '    -c "%s" \\\n'  "$NF_CONFIG"
    printf '    -c "%s" \\\n'  "$SEQINSPECTOR_CONFIG"
    printf '    --project ngi2016003 \\\n'
    printf '    --igenomes_base /sw/data/igenomes/ \\\n'
    printf '    --input "%s" \\\n' "$samplesheet_path"
    printf '    --outdir "%s" \\\n' "$pipeline_outdir"
    printf '    --fastq_screen_references "%s" \\\n' "$FASTQ_SCREEN_REFERENCES"
    [[ -n "${NF_WORKDIR:-}" ]] && printf '    -w "%s" \\\n' "$NF_WORKDIR"
    printf '    --skip_tools bwamem2_index,bwamem2_mem,picard_collectmultiplemetrics,samtools_faidx,samtools_index,seqfu_stats\n'
else
    [[ -n "${NF_LAUNCHDIR:-}" ]] && { mkdir -p "$NF_LAUNCHDIR"; cd "$NF_LAUNCHDIR"; }
    echo "[$(date)] Starting seqinspector pipeline..."
    "${nf_command[@]}"
    echo "[$(date)] seqinspector pipeline completed."
fi
