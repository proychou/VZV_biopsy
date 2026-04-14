#!/bin/bash
#SBATCH --job-name=tab_counts
#SBATCH --partition=campus-new
#SBATCH -c 2
#SBATCH --mem=8G
#SBATCH -t 02:00:00
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=ssathees@fredhutch.org
set -euo pipefail

module load SAMtools/1.17 2>/dev/null || module load SAMtools 2>/dev/null || true
command -v samtools >/dev/null || { echo "samtools not available"; exit 1; }

ROOT="${SLURM_SUBMIT_DIR:-$PWD}"
FILT_ROOT="${ROOT}/filtered_reads"
MAP_ROOT="${ROOT}/mapped_reads"
OUT="${ROOT}/read_counts.csv"

echo "Sample,Filtered_Reads_R2,Mapped_Reads_R2" > "$OUT"

# loop each sample folder existing under filtered_reads
shopt -s nullglob
for samp_dir in "${FILT_ROOT}"/*; do
  [[ -d "$samp_dir" ]] || continue
  samp="$(basename "$samp_dir")"

  # ---- count filtered reads (sum all matched R2 fastqs) ----
  filtered_total=0
  for fq in "${FILT_ROOT}/${samp}"/*_R2_matched*.fastq.gz "${FILT_ROOT}/${samp}"/*_R2_matched*.fq.gz; do
    [[ -f "$fq" ]] || continue
    # fastq has 4 lines per read
    nlines=$(zcat "$fq" | wc -l)
    nreads=$(( nlines / 4 ))
    filtered_total=$(( filtered_total + nreads ))
  done

  # ---- count mapped reads (sum across BAMs) ----
  mapped_total=0
  for bam in "${MAP_ROOT}/${samp}"/*.bam; do
    [[ -f "$bam" ]] || continue
    # count reads with the "mapped" bit set (exclude unmapped)
    nmap=$(samtools view -c -F 4 "$bam")
    mapped_total=$(( mapped_total + nmap ))
  done

  # write row (sample, filtered, mapped)
  echo "${samp},${filtered_total},${mapped_total}" >> "$OUT"
done

echo "Wrote: $OUT"
echo "Tip: Excel opens CSV directly."
