#!/bin/bash

# --- Simple Configuration ---
POLL_SIMUL_EXEC="./poll_simul"
OUTPUT_FILE="data.dat"
RUN_SECONDS=5

# Path to CPU0 available DVFS frequencies (kHz)
AVAIL_FREQ_FILE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies"

set -euo pipefail

# Check simulator exists
[[ -x "$POLL_SIMUL_EXEC" ]] || { echo "Error: '$POLL_SIMUL_EXEC' not found."; exit 1; }

# Count cores on socket 0
TOTAL_ACTIVE_CORES=$(lscpu -p=CPU,CORE,SOCKET \
  | awk -F, '$3==0 && $1!~/^#/ {print}' | wc -l)
[[ "$TOTAL_ACTIVE_CORES" =~ ^[0-9]+$ ]] || { echo "Error: cannot determine cores."; exit 1; }

# Read and sort available frequencies, filter out any blank or non-numeric
[[ -f "$AVAIL_FREQ_FILE" ]] || { echo "Error: '$AVAIL_FREQ_FILE' missing."; exit 1; }
mapfile -t FREQS < <(
    tr ' ' '\n' < "$AVAIL_FREQ_FILE" \
    | grep -E '^[0-9]+$' \
    | sort -nr
)

# Ensure we have at least one frequency
if [ ${#FREQS[@]} -eq 0 ]; then
    echo "Error: no valid frequencies found in $AVAIL_FREQ_FILE"
    exit 1
fi

# Clear output file (only poll_simul output goes here)
> "$OUTPUT_FILE"

# Run experiments
for (( cores=TOTAL_ACTIVE_CORES; cores>=1; cores-- )); do
  for bw in 100 50 25 10 5 1; do
    for freq in "${FREQS[@]}"; do
      echo "Run: cores=$cores bw=$bw freq=$freq"
      ./resctl.sh "$cores" "$bw" "$freq"
      "$POLL_SIMUL_EXEC" "$TOTAL_ACTIVE_CORES" "$RUN_SECONDS" \
        "$cores" "$bw" "$freq" >> "$OUTPUT_FILE"
    done
  done
done

echo "Done. Results in $OUTPUT_FILE."

