#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <base_directory>"
    exit 1
fi

base_dir="${1%/}"
flowcell=$(basename "$base_dir")
flowcell="${flowcell##*_}"

# Associative arrays for storing R1 and R2 paths for regular samples
declare -A r1_files
declare -A r2_files

# Associative arrays for undetermined reads, keyed by lane (e.g. "lane1")
declare -A undet_r1
declare -A undet_r2

# Find all FASTQ files and route them to the appropriate arrays
while IFS= read -r file; do

    filename=$(basename "$file")

    # Handle Undetermined reads separately (live directly in Demultiplexing/)
    # Expected pattern: Undetermined_S0_L001_R1_001.fastq.gz
    if [[ "$filename" =~ ^[Uu]ndetermined.*_L([0-9]+)_R([12])_[0-9]+\.fastq\.gz$ ]]; then
        lane_num="${BASH_REMATCH[1]#0}"   # strip leading zeros (001 → 1)
        lane_key="lane${lane_num}"
        read="${BASH_REMATCH[2]}"

        if [[ "$read" == "1" ]]; then
            undet_r1["$lane_key"]="$file"
        else
            undet_r2["$lane_key"]="$file"
        fi
        continue
    fi

    # Only process regular R1/R2 files
    if [[ "$filename" =~ ^(.+)_R([12])_[0-9]+\.fastq\.gz$ ]]; then

        key="${BASH_REMATCH[1]}"
        read="${BASH_REMATCH[2]}"

        if [[ "$read" == "1" ]]; then
            r1_files["$key"]="$file"
        else
            r2_files["$key"]="$file"
        fi

    fi

done < <(find "${base_dir}/Demultiplexing" -type f -name "*.fastq.gz" | sort)


# Write header line
printf "sample,fastq_1,fastq_2,rundir,tags\n"


# --- Regular samples ---

# Combine all keys from R1 and R2
keys=$(printf "%s\n%s\n" \
    "${!r1_files[@]}" \
    "${!r2_files[@]}" | sort -u)

while IFS= read -r key; do

    [[ -z "$key" ]] && continue

    r1="${r1_files[$key]:-}"
    r2="${r2_files[$key]:-}"

    # Extract sample directory
    if [[ "$r1" != "" ]]; then
        sample_dir=$(dirname "$r1")
    else
        sample_dir=$(dirname "$r2")
    fi

    sample=$(basename "$sample_dir")
    sample="${sample#Sample_}"

    # Extract lane from key (e.g. SampleName_S1_L001 → lane1)
    lane_num="unknown"
    if [[ "$key" =~ _L([0-9]+) ]]; then
        lane_num="${BASH_REMATCH[1]#0}"
    fi
    sample="${sample}_${flowcell}_lane${lane_num}"

    # Extract batch directory
    batch=$(basename "$(dirname "$sample_dir")")

    printf "%s,%s,%s,%s,%s\n" \
        "$sample" \
        "$r1" \
        "$r2" \
        "$base_dir" \
        "$batch"

done <<< "$keys"


# --- Undetermined reads ---

# Collect all lane keys from both R1 and R2 undetermined arrays
undet_keys=$(printf "%s\n%s\n" \
    "${!undet_r1[@]}" \
    "${!undet_r2[@]}" | sort -u)

while IFS= read -r lane_key; do

    [[ -z "$lane_key" ]] && continue

    r1="${undet_r1[$lane_key]:-}"
    r2="${undet_r2[$lane_key]:-}"

    printf "%s,%s,%s,%s,%s\n" \
        "undetermined_${flowcell}_${lane_key}" \
        "$r1" \
        "$r2" \
        "$base_dir" \
        "undetermined"

done <<< "$undet_keys"
