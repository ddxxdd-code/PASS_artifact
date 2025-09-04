#!/bin/bash

# --- Simple Configuration ---
POLL_SIMUL_EXEC="./poll_simul"
OUTPUT_FILE="data.dat"
RUN_SECONDS=5
# Path to the file containing the maximum RAPL power limit in microwatts for socket 0
# >>> IMPORTANT: Make sure this path is correct for your system! <<<
MAX_RAPL_FILE="/sys/class/powercap/intel-rapl/intel-rapl:0/constraint_0_max_power_uw"
# Define MINIMUM and DECREMENT as **INTEGERS**
MIN_RAPL_W=20
RAPL_DECREMENT=20

# --- Basic Setup & Checks ---
set -e # Exit script immediately if any command fails

# Check if poll_simul exists and is executable
if [ ! -x "$POLL_SIMUL_EXEC" ]; then
    echo "Error: Executable '$POLL_SIMUL_EXEC' not found or not executable in the current directory."
    exit 1
fi

# Get total cores
TOTAL_ACTIVE_CORES=$(lscpu --parse=socket | grep -v '^#' | awk -F, '$1 == 1' | wc -l)
if ! [[ "$TOTAL_ACTIVE_CORES" =~ ^[0-9]+$ ]] || [ "$TOTAL_ACTIVE_CORES" -le 0 ]; then
    echo "Error: Could not determine a valid number of active cores using 'nproc'."
    exit 1
fi
echo "Detected $TOTAL_ACTIVE_CORES total active cores."

# --- Get Max RAPL (as Integer Watts) ---
if [ ! -f "$MAX_RAPL_FILE" ]; then
    echo "Error: Cannot find RAPL max power file: '$MAX_RAPL_FILE'"
    echo "Please verify the path and RAPL support."
    exit 1
fi
MAX_RAPL_UW=$(cat "$MAX_RAPL_FILE")
# Use bash integer arithmetic for division (truncates result)
MAX_RAPL_W=$(( MAX_RAPL_UW / 1000000 ))

# Check if calculated Max Power is valid
if [ "$MAX_RAPL_W" -le 0 ]; then
     echo "Error: Max RAPL power calculated as $MAX_RAPL_W W (from $MAX_RAPL_UW uW). Check $MAX_RAPL_FILE."
     exit 1
fi

# Handle case where system Max RAPL is less than our desired Min
if [ "$MAX_RAPL_W" -lt "$MIN_RAPL_W" ]; then
    echo "Warning: Max system RAPL ($MAX_RAPL_W W) is less than Min test value ($MIN_RAPL_W W). Adjusting Max to $MIN_RAPL_W W for the loop."
    MAX_RAPL_W=$MIN_RAPL_W
fi
echo "Using Max RAPL (Integer): $MAX_RAPL_W W, Min RAPL: $MIN_RAPL_W W, Decrement: $RAPL_DECREMENT W"


# --- Prepare Output File ---
echo "Clearing previous results in $OUTPUT_FILE..."
> "$OUTPUT_FILE"
echo "Starting evaluations..."

# --- Parameter Loops ---

# Loop Cores: Total down to 1
for (( num_cores=TOTAL_ACTIVE_CORES; num_cores>=1; num_cores-- )); do

    # Loop Bandwidth: 100, 50, 25, 10, 5, 1
    for bandwidth in 100 50 25 10 5 1; do

        # Loop RAPL Power (Integer Watts): Max down by 20, stops when less than Min
        for (( rapl_w = MAX_RAPL_W; rapl_w >= MIN_RAPL_W; rapl_w -= RAPL_DECREMENT )); do
            # Execute the simulation command
            # Output from poll_simul is appended directly to the file
	    ./init_cgroup_rapl.sh
	    ./resctl.sh $num_cores $bandwidth $rapl_w
            "$POLL_SIMUL_EXEC" "$TOTAL_ACTIVE_CORES" "$RUN_SECONDS" "$num_cores" "$bandwidth" "$rapl_w" >> "$OUTPUT_FILE"
            # If a command fails, 'set -e' will cause the script to exit.
            # Remove 'set -e' and add error handling here if you want it to continue.
            # Example: || echo "Warning: Failed Cores=$num_cores BW=$bandwidth RAPL=$rapl_w"

        done # End RAPL loop

    done # End Bandwidth loop
done # End Cores loop

echo "Evaluation complete. Results are in $OUTPUT_FILE"

exit 0
