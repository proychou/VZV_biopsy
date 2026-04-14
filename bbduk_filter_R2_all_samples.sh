#!/bin/bash
#SBATCH --partition=campus-new
#SBATCH -c 14
#SBATCH -t 7-00:00:00
#SBATCH --mem=280G
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=ssathees@fredhutch.org

module load BBMap/38.97-GCC-10.2.0
set -euo pipefail

echo "Number of cores used: ${SLURM_CPUS_PER_TASK:-unset}"

# Parse flags: -2 R2 (required), -s sample (required). -1 accepted but ignored.
r1=""; r2=""; samp=""
while getopts "1:2:s:" opt; do
  case $opt in
    1) r1="$OPTARG" ;;
    2) r2="$OPTARG" ;;
    s) samp="$OPTARG" ;;
    \?) echo "Invalid option -$OPTARG" >&2 ; exit 1 ;;
  esac
done

[[ -n "${r2}" ]]   || { echo "ERROR: -2 R2_FASTQ required"; exit 1; }
[[ -n "${samp}" ]] || { echo "ERROR: -s SAMPLE_NAME required"; exit 1; }

printf "Input arguments:\n\n"; echo "$@"

# ---- project root and per-sample work dir ----
ROOT="${SLURM_SUBMIT_DIR:-$(pwd)}"             # where sbatch was called
workdir="${ROOT}/${samp}_work"                 # temp scratch for this sample
mkdir -p "$workdir"
cd "$workdir"

# ---- S3 download (handles spaces) ----
if [[ "${r2}" == s3://* ]]; then
  echo "Detected S3 R2 input; downloading locally..."
  r2base="$(basename "$r2")"
  r2local="${samp}_${r2base}"
  aws s3 cp "$r2" "$r2local"
  r2="$r2local"
fi

# ---- name derivations ----
t2="$(basename "$r2" | sed 's/_R2/_R2_trimmed/')"
uf2="$(basename "$r2" | sed 's/_R2/_R2_unmatched/')"
mf2="$(basename "$r2" | sed 's/_R2/_R2_matched/')"
statf="$(basename "$r2" | sed -E 's/_R2_001\.f(ast)?q(\.gz)?$//')"

# ---- output dirs under ROOT (your desired structure) ----
TRIM_DIR="${ROOT}/trimmed_reads/${samp}"
FILT_DIR="${ROOT}/filtered_reads/${samp}"
MAP_DIR="${ROOT}/mapped_reads/${samp}"
mkdir -p "$TRIM_DIR" "$FILT_DIR" "$MAP_DIR"

echo "Writing outputs to:"
echo "  $TRIM_DIR"
echo "  $FILT_DIR"
echo "  $MAP_DIR"

# 1) Trim R2
bbduk.sh \
  in="$r2" \
  out="${TRIM_DIR}/${t2}" \
  stats="${TRIM_DIR}/${statf}_stats.txt" \
  overwrite=TRUE t="${SLURM_CPUS_PER_TASK:-1}" \
  k=27 hdist=1 edist=0 mink=4 ktrim=r ref=adapters,artifacts,phix \
  qtrim=rl trimq=20 minlength=35 entropy=0.1 entropywindow=50 entropyk=5 qin=33

# 2) Filter R2 against reference
bbduk.sh \
  in="${TRIM_DIR}/${t2}" \
  out="${FILT_DIR}/${uf2}" \
  outm="${FILT_DIR}/${mf2}" \
  ref="/home/ssathees/vzv/ref/vzv_ref.fasta" \
  k=31 hdist=2 \
  stats="${FILT_DIR}/${statf}_stats.txt" \
  overwrite=TRUE t="${SLURM_CPUS_PER_TASK:-1}"

# 3) Remove unmatched to save space
rm -f "${FILT_DIR}/${uf2}"

# 4) Map the matched R2 reads (unsorted BAM as requested)
bbmap.sh \
  in="${FILT_DIR}/${mf2}" \
  out="${MAP_DIR}/${statf}_mapped_to_vzv.bam" \
  ref="/home/ssathees/vzv/ref/vzv_ref.fasta" \
  overwrite=TRUE t="${SLURM_CPUS_PER_TASK:-1}"

# Optional: drop the local FASTQ to save space if it came from S3
#[[ "${r2local:-}" ]] && rm -f "${r2local}" || true
