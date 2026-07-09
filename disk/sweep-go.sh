#!/usr/bin/env bash
#
# sweep-go.sh — Run the Go benchmark across the same matrix as sweep.sh.
#
# Results are saved in results/go-<bs>-<iodepth>.json
#
# Usage:
#   ./sweep-go.sh
#   BLOCK_SIZES="4k 1M" IO_DEPTHS="1 32" ./sweep-go.sh

set -euo pipefail

TESTFILE="${TESTFILE:-./fio-testfile}"
RESULTS_DIR="${RESULTS_DIR:-results}"
BLOCK_SIZES_STR="${BLOCK_SIZES:-256k 1M 4M}"
IO_DEPTHS_STR="${IO_DEPTHS:-1 4 8 16 32 64}"

mkdir -p "$RESULTS_DIR"

# Convert block size strings (e.g. "4k") to bytes
bs_to_bytes() {
    local bs="$1"
    local num="${bs%[kKMgG]}"
    local unit="${bs: -1}"
    case "$unit" in
        k|K) echo $(( num * 1024 )) ;;
        M|m) echo $(( num * 1024 * 1024 )) ;;
        G|g) echo $(( num * 1024 * 1024 * 1024 )) ;;
        *)   echo "$num" ;;
    esac
}

read -ra BLOCK_SIZES <<< "$BLOCK_SIZES_STR"
read -ra IO_DEPTHS <<< "$IO_DEPTHS_STR"

echo "==> Test file  : ${TESTFILE}"
echo "==> Results dir: ${RESULTS_DIR}/"
echo "==> Block sizes: ${BLOCK_SIZES[*]}"
echo "==> IO depths  : ${IO_DEPTHS[*]}"
echo "==> Total runs : $(( ${#BLOCK_SIZES[@]} * ${#IO_DEPTHS[@]} ))"
echo

# ---- Build optimized binary ------------------------------------------------
echo "==> Building optimized benchmark binary..."
go build -o /tmp/bench-opt -gcflags="-B" -ldflags="-s -w" ./bench

BENCH_BIN=/tmp/bench-opt
echo "==> Using binary: ${BENCH_BIN}"
echo

for bs in "${BLOCK_SIZES[@]}"; do
    bs_bytes=$(bs_to_bytes "$bs")
    for depth in "${IO_DEPTHS[@]}"; do
        out="${RESULTS_DIR}/go-${bs}-${depth}.json"
        echo "--- bs=${bs}(${bs_bytes}B) iodepth=${depth} → ${out}"

        "$BENCH_BIN" -bs "$bs_bytes" -depth "$depth" -output "$out"

        time_s=$(jq -r '.time_s' "$out" 2>/dev/null || echo '?')
        echo "    time=${time_s}s"
    done
done

echo
echo "==> Go sweep complete. Run ./plot.py to generate the comparison graph."
