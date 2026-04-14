#!/bin/bash
set -euo pipefail

# Per-sample pipeline
script="bbduk_filter_R2_all_samples.sh"

# Split bucket and prefix (no leading/trailing slashes in prefix)
bucket="fh-pi-jerome-k-eco"
s3_prefix="jeromelab/Lichen_10X/401 biopsy fastqs for Pavitra"

# List objects under the prefix, keep full key (with spaces), build full s3:// URL
aws s3 ls "s3://${bucket}/${s3_prefix}/" --recursive \
| awk '{
    # drop date, time, size; keep rest as the full key (even if it has spaces)
    $1=$2=$3=""; sub(/^   /,""); print
  }' \
| awk -v bucket="$bucket" -v prefix="$s3_prefix" '
    END { if (NR==0) { print "No R2 files found on S3" > "/dev/stderr"; exit 1 } }
    # Only keep keys beneath our prefix (defensive), then filter for R2
    index($0, prefix "/")==1 && /_R2_001\.fastq\.gz$/ {
        print "s3://" bucket "/" $0
    }' \
| while IFS= read -r r2; do
    base="$(basename "$r2")"
    samp="$(echo "$base" | sed -E 's/_R2_001\.f(ast)?q(\.gz)?$//')"
    echo "Submitting: $samp  ->  $r2"
    sbatch "$script" -2 "$r2" -s "$samp"
  done
