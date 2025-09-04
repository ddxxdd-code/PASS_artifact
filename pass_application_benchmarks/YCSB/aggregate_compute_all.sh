#!/usr/bin/env bash
#
# run_all_caps.sh
# ───────────────
# Loop through every <config, powercap> combination and run:
#   1. ./compute_aggregated_all_workloads_bandwidths_method_and_cap.sh
#   2. python3 merge_aggregated_throughput_method_and_cap.py
#
# Edit CONFIGS or POWERCAPS if you need different values.

set -euo pipefail

CONFIGS=(
  cpu_rapl
  cpu_thunderbolt
  linux_rapl
  pass_profiled_new_new
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
    echo "Running: config=${cfg}, powercap=${cap}"
    echo "─────────────────────────────────────────────────────────"

    # 1. aggregate bandwidths for all workloads
    ./compute_aggregated_all_workloads_bandwidths_method_and_cap.sh -m "${cfg}" -c "${cap}"

    # 2. merge the per-workload CSVs into one file
    python3 merge_aggregated_throughput_method_and_cap.py           -m "${cfg}" -c "${cap}"

    echo "✓ Done for ${cfg} @ ${cap}W"
    echo
  done
done

echo "All combinations finished."
