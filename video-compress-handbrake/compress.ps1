# RUN: powershell -ExecutionPolicy Bypass -File compress.ps1
# ============================================================
# Parallel Video Compression Script for PowerShell 5.1
# Features:
# - Recursive video processing
# - Skips already compressed files (size > 0)
# - Uses Start-Job for parallel execution (PowerShell 5.1 compatible)
# - Shows progress: task N of total, original size -> compressed size
# - Preserves folder structure in output
# - Reduces resolution to 720p for faster compression
# ============================================================

# -----------------------------
# User Configuration
# -----------------------------
$inputDir = "C:\Users\david\Videos\Captures"       # Source folder
$outputDir = "C:\Users\david\Videos\Compressed"   # Destination folder
$maxParallel = 4                                   # Max parallel jobs (Start-Job is heavier, keep low)

# -----------------------------
# Get all video files recursively
# -----------------------------
$videos = Get-ChildItem $inputDir -File -Include *.mp4, *.mov, *.mkv, *.avi -Recurse
$total = $videos.Count
$counter = 0

# Initialize job array
$jobs = @()

# -----------------------------
# Loop through videos
# -----------------------------
foreach ($video in $videos) {

    $counter++
    $name = $video.Name
    $src = $video.FullName

    # Preserve folder structure in output
    $relativePath = $video.FullName.Substring($inputDir.Length).TrimStart("\")
    $dst = Join-Path $outputDir $relativePath

    # Ensure output folder exists
    $dstFolder = Split-Path $dst -Parent
    if (-not (Test-Path $dstFolder)) {
        New-Item -ItemType Directory -Path $dstFolder | Out-Null
    }

    # Skip if output exists and size > 0
    if (Test-Path $dst -PathType Leaf) {
        $outSize = (Get-Item $dst).Length
        if ($outSize -gt 0) {
            Write-Host "SKIP: $relativePath already exists."
            continue
        }
    }

    # -----------------------------
    # Start compression as a background job
    # -----------------------------
    $job = Start-Job -ScriptBlock {
        param($src, $dst, $name, $index, $total, $inputDir, $outputDir, $relativePath)

        # Helper function: human-readable file size
        function HumanSize($bytes) {
            switch ($bytes) {
                {$_ -gt 1GB} { return "{0:N2} GB" -f ($bytes / 1GB) }
                {$_ -gt 1MB} { return "{0:N2} MB" -f ($bytes / 1MB) }
                {$_ -gt 1KB} { return "{0:N2} KB" -f ($bytes / 1KB) }
                default      { return "$bytes B" }
            }
        }

        # Original file size
        $origSize = (Get-Item $src).Length

        # -----------------------------
        # Docker HandBrakeCLI compression
        # -----------------------------
        docker run --rm `
          -v "${inputDir}:/input" `
          -v "${outputDir}:/output" `
          jlesage/handbrake `
          HandBrakeCLI -i "/input/$relativePath" -o "/output/$relativePath" `
              -e x264 -q 22 --optimize --height 480 --keep-display-aspect

        # Compressed file size
        $newSize = (Get-Item $dst).Length
        $origHr = HumanSize $origSize
        $newHr = HumanSize $newSize

        return "DONE [$index/$total]: $relativePath | $origHr → $newHr"

    } -ArgumentList $src, $dst, $name, $counter, $total, $inputDir, $outputDir, $relativePath

    $jobs += $job

    # -----------------------------
    # Throttle parallel jobs
    # -----------------------------
    while (($jobs | Where-Object State -eq 'Running').Count -ge $maxParallel) {
        Start-Sleep -Seconds 2
    }
}

# -----------------------------
# Wait for remaining jobs and collect results
# -----------------------------
if ($jobs.Count -gt 0) {
    # Wait for all jobs to finish
    $jobs | Wait-Job

    # Retrieve output from jobs
    $jobs | Receive-Job | ForEach-Object { Write-Host $_ }

    # Clean up jobs
    $jobs | Remove-Job -Force
} else {
    Write-Host "No new files to process. All videos already compressed."
}

# -----------------------------
# End of Script
# -----------------------------