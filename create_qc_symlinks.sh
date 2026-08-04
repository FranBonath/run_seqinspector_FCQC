#!/usr/bin/env bash
# create_qc_symlinks.sh
#
# Creates per-file symlinks of seqinspector QC results into the project
# analysis directories on the HPC.
#
# Processed result subdirectories: fastqc, fastqscreen
# Ignored result subdirectories:   multiqc, pipeline_info, rundirparser
#
# Project IDs (e.g. P12345) are extracted from the first '_'-delimited field
# of each sample name in the samplesheet. The project ID names the analysis
# directory and is used to match result files (pattern: "*<project_id>_*").
#
# Target structure:
#   <analysis_base>/<project_id>/qc_ngi/<fastqc|fastqscreen>/<file>
#       -> <results_dir>/<fastqc|fastqscreen>/<file>
#
# Usage:
#   bash create_qc_symlinks.sh -b <analysis_base> -r <results_dir> [-s <samplesheet>] [-p <project_id> ...] [--dry-run]
#
# Options:
#   -b          Base path for project analysis directories (required).
#   -r          Path to the seqinspector results directory (required).
#   -s          Path to the samplesheet CSV used for the run. Required if -p is not given.
#   -p          Project ID to include (e.g. P12345). Repeat for multiple.
#               Required if -s is not given. If used with -s, validated against the samplesheet.
#   --dry-run   Print actions without creating any directories or symlinks.

set -euo pipefail

# Result subdirectories to process (all others are ignored)
PROCESS_DIRS=("fastqc" "fastqscreen")

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 -b <analysis_base> -r <results_dir> [-s <samplesheet>] [-p <project_id> ...] [--dry-run]"
    exit 1
}

analysis_base=""
results_dir=""
samplesheet=""
dry_run=false
declare -A filter_projects=()

args=()
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        dry_run=true
    else
        args+=("$arg")
    fi
done
(( ${#args[@]} > 0 )) && set -- "${args[@]}" || set --

while getopts ":b:r:s:p:" opt; do
    case $opt in
        b) analysis_base="$OPTARG" ;;
        r) results_dir="$OPTARG"   ;;
        s) samplesheet="$OPTARG"   ;;
        p) filter_projects["$OPTARG"]=1 ;;
        *) usage ;;
    esac
done

[[ -z "$analysis_base" ]] && { echo "Error: -b <analysis_base> is required."; usage; }
[[ -z "$results_dir" ]]   && { echo "Error: -r <results_dir> is required.";   usage; }

if [[ -z "$samplesheet" && ${#filter_projects[@]} -eq 0 ]]; then
    echo "Error: either -s <samplesheet> or at least one -p <project_id> is required."
    usage
fi

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------

results_dir="${results_dir%/}"

if [[ ! -d "$results_dir" ]]; then
    echo "Error: results directory not found: $results_dir"
    exit 1
fi

if [[ -n "$samplesheet" && ! -f "$samplesheet" ]]; then
    echo "Error: samplesheet not found: $samplesheet"
    exit 1
fi

# ---------------------------------------------------------------------------
# Collect unique project IDs from the samplesheet (skip undetermined)
# ---------------------------------------------------------------------------

declare -A projects=()

if [[ -n "$samplesheet" ]]; then
    # CSV format: sample,fastq_1,fastq_2,rundir,tags
    while IFS=',' read -r sample _fastq1 _fastq2 _rundir tags; do
        [[ "$sample" == "sample" ]] && continue          # header row
        [[ "$tags" == "undetermined" ]] && continue      # undetermined reads
        sample="${sample%%$'\r'}"                        # strip any Windows line endings
        [[ -z "$sample" ]] && continue

        # Project ID = first '_'-delimited field of the sample name (e.g. P12345)
        project_id="${sample%%_*}"
        [[ -z "$project_id" ]] && continue

        projects["$project_id"]=1
    done < "$samplesheet"

    if [[ ${#projects[@]} -eq 0 ]]; then
        echo "Warning: no non-undetermined projects found in $samplesheet — nothing to do."
        exit 0
    fi

    # If -p was specified, restrict to those project IDs and validate against samplesheet
    if [[ ${#filter_projects[@]} -gt 0 ]]; then
        for pid in "${!filter_projects[@]}"; do
            [[ -z "${projects[$pid]:-}" ]] && \
                echo "Warning: project '$pid' (given with -p) was not found in the samplesheet — skipping."
        done
        for pid in "${!projects[@]}"; do
            [[ -z "${filter_projects[$pid]:-}" ]] && unset "projects[$pid]"
        done
        if [[ ${#projects[@]} -eq 0 ]]; then
            echo "Error: none of the requested projects were found in the samplesheet."
            exit 1
        fi
    fi
else
    # No samplesheet — use -p project IDs directly
    for pid in "${!filter_projects[@]}"; do
        projects["$pid"]=1
    done
fi

# ---------------------------------------------------------------------------
# Create per-file symlinks
# ---------------------------------------------------------------------------

results_dir_abs="$(cd "$results_dir" && pwd)"

echo "[$(date)] Results dir : $results_dir_abs"
echo "[$(date)] Projects    : ${!projects[*]}"
echo "[$(date)] Directories : ${PROCESS_DIRS[*]}"
echo ""

for project_id in "${!projects[@]}"; do
    echo "[$(date)] Processing project: $project_id"

    for subdir in "${PROCESS_DIRS[@]}"; do
        src_dir="${results_dir_abs}/${subdir}"

        if [[ ! -d "$src_dir" ]]; then
            echo "  [skip] $subdir — not found in results directory"
            continue
        fi

        target_dir="${analysis_base}/${project_id}/qc_ngi/${subdir}"

        if [[ "$dry_run" == true ]]; then
            echo "  [dry-run] mkdir -p \"$target_dir\""
        else
            mkdir -p "$target_dir"
        fi

        # Find files whose name contains "<project_id>_" (anywhere in filename)
        matched=0
        while IFS= read -r file; do
            link_path="${target_dir}/$(basename "$file")"
            (( matched++ )) || true

            if [[ "$dry_run" == true ]]; then
                echo "  [dry-run] ln -s \"$file\" \"$link_path\""
                continue
            fi

            if [[ -L "$link_path" ]]; then
                echo "  [skip] symlink already exists: $(basename "$file")"
            elif [[ -e "$link_path" ]]; then
                echo "  Warning: path exists and is not a symlink, skipping: $link_path"
            else
                ln -s "$file" "$link_path"
                echo "  [link] $(basename "$file")"
            fi
        done < <(find "$src_dir" -type f -name "*${project_id}_*")

        if [[ $matched -eq 0 ]]; then
            echo "  [skip] $subdir — no files matching '${project_id}_' found"
        fi
    done

    echo ""
done

[[ "$dry_run" == true ]] && echo "[$(date)] Dry run complete — no changes were made." \
                         || echo "[$(date)] Done."
