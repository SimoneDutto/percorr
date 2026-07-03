#!/usr/bin/env bash
#
# sweep.sh — Run fio across a matrix of block sizes and io depths.
#
# Results are saved in results/sweep-<bs>-<iodepth>.json
#
# Usage:
#   ./sweep.sh                    # default matrix, 10s per run
#   RUNTIME=30 ./sweep.sh         # longer runs
#   TESTFILE=/mnt/data/tf ./sweep.sh

set -euo pipefail

TESTFILE="${TESTFILE:-./fio-testfile}"
RUNTIME="${RUNTIME:-10}"
RESULTS_DIR="${RESULTS_DIR:-results}"
mkdir -p "$RESULTS_DIR"

# The matrix to sweep.
BLOCK_SIZES=(4k 64k 256k 1M 4M)
IO_DEPTHS=(1 4 8 16 32 64)

echo "==> Test file  : ${TESTFILE}"
echo "==> Results dir: ${RESULTS_DIR}/"
echo "==> Runtime    : ${RUNTIME}s per run"
echo "==> Block sizes: ${BLOCK_SIZES[*]}"
echo "==> IO depths  : ${IO_DEPTHS[*]}"
echo "==> Total runs : $(( ${#BLOCK_SIZES[@]} * ${#IO_DEPTHS[@]} ))"
echo

for bs in "${BLOCK_SIZES[@]}"; do
    for depth in "${IO_DEPTHS[@]}"; do
        out="${RESULTS_DIR}/sweep-${bs}-${depth}.json"
        echo "--- bs=${bs} iodepth=${depth} → ${out}"

        fio --name=sweep \
            --filename="$TESTFILE" \
            --rw=read \
            --ioengine=libaio \
            --iodepth="$depth" \
            --bs="$bs" \
            --direct=1 \
            --time_based \
            --runtime="${RUNTIME}s" \
            --loops=1000 \
            --group_reporting \
            --output-format=json \
            --output="$out" 2>/dev/null

        # Quick one-liner so you see progress.
        bw=$(jq -r '.jobs[0].read.bw' "$out" 2>/dev/null || echo '?')
        echo "    bw=${bw} KiB/s"
    done
done

echo
echo "==> Sweep complete. Run ./plot.py to generate the graph."
