#!/usr/bin/env bash
# RUN: bash compress.sh
# ============================================================
# Parallel Video Compression Script for Bash
# Features:
# - Recursive video processing
# - Skips already compressed files (size > 0)
# - Uses background processes for parallel execution
# - Shows progress: task N of total, original size -> compressed size
# - Preserves folder structure in output
# - Reduces resolution to 480p for faster compression
# ============================================================

# -----------------------------
# User Configuration
# -----------------------------
INPUT_DIR="$HOME/Videos/Screencasts"       # Source folder
OUTPUT_DIR="$HOME/Videos/Compressed"    # Destination folder
MAX_PARALLEL=4                          # Max parallel jobs

# -----------------------------
# Helper: human-readable file size
# -----------------------------
human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.2f GB" "$(echo "scale=2; $bytes / 1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.2f MB" "$(echo "scale=2; $bytes / 1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.2f KB" "$(echo "scale=2; $bytes / 1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# -----------------------------
# Compress a single video
# -----------------------------
compress_video() {
    local src="$1"
    local dst="$2"
    local relative="$3"      # input relative path (may be .webm)
    local out_relative="$4"   # output relative path (.webm converted to .mp4)
    local index="$5"
    local total="$6"

    local orig_size
    orig_size=$(stat -c%s "$src")

    docker run --rm \
        -v "${INPUT_DIR}:/input" \
        -v "${OUTPUT_DIR}:/output" \
        jlesage/handbrake \
        HandBrakeCLI -i "/input/${relative}" -o "/output/${out_relative}" \
            -e x264 -q 22 --optimize --height 480 --keep-display-aspect

    local new_size
    new_size=$(stat -c%s "$dst")
    local orig_hr new_hr
    orig_hr=$(human_size "$orig_size")
    new_hr=$(human_size "$new_size")

    echo "DONE [$index/$total]: $out_relative | $orig_hr → $new_hr"
}

# -----------------------------
# Get all video files recursively
# -----------------------------
mapfile -t videos < <(find "$INPUT_DIR" -type f \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.webm' \) | sort)
total=${#videos[@]}
counter=0
pids=()

if (( total == 0 )); then
    echo "No video files found in $INPUT_DIR."
    exit 0
fi

# -----------------------------
# Loop through videos
# -----------------------------
for src in "${videos[@]}"; do
    ((counter++))

    # Preserve folder structure in output, converting .webm to .mp4
    relative="${src#"$INPUT_DIR"/}"
    out_relative="${relative/%.[wW][eE][bB][mM]/.mp4}"
    dst="${OUTPUT_DIR}/${out_relative}"
    dst_folder="$(dirname "$dst")"

    # Ensure output folder exists
    mkdir -p "$dst_folder"

    # Skip if output exists and size > 0
    if [[ -f "$dst" ]] && (( $(stat -c%s "$dst") > 0 )); then
        echo "SKIP: $out_relative already exists."
        continue
    fi

    # -----------------------------
    # Throttle parallel jobs
    # -----------------------------
    while (( ${#pids[@]} >= MAX_PARALLEL )); do
        # Wait for any one job to finish, then remove completed pids
        local_pids=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                local_pids+=("$pid")
            else
                wait "$pid"
            fi
        done
        pids=("${local_pids[@]}")
        if (( ${#pids[@]} >= MAX_PARALLEL )); then
            sleep 2
        fi
    done

    # -----------------------------
    # Start compression in background
    # -----------------------------
    compress_video "$src" "$dst" "$relative" "$out_relative" "$counter" "$total" &
    pids+=($!)
done

# -----------------------------
# Wait for remaining jobs
# -----------------------------
for pid in "${pids[@]}"; do
    wait "$pid"
done

if (( counter == 0 )); then
    echo "No new files to process. All videos already compressed."
fi

echo "All done."
