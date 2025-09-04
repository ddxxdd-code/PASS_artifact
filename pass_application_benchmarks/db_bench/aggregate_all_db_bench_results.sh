#!/usr/bin/env bash
# run_aggregate_all.sh
# ───────────────────
# Loop over all configs and power-caps, invoking:
#   python3 aggregate_db_bench_throughput_p99.py -s <config> -c <cap>

set -euo pipefail

CONFIGS=(
  spdk_rapl
  spdk_thunderbolt
  linux_rapl
  pass_profiled
)

POWERCAPS=(
  265
  280
  330
  375
  470
)

for cfg in "${CONFIGS[@]}"; do
  for cap in "${POWERCAPS[@]}"; do
    echo "─────────────────────────────────────────────────────────"
    echo "Aggregating: config=${cfg}, powercap=${cap} W"
    python3 aggregate_db_bench_throughput_p99.py -s "${cfg}" -c "${cap}"
  done
done

echo "All combinations processed."
