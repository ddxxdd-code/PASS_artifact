#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 -s|--scheduler <scheduler>"
    exit 1
}

# Parse input arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--scheduler)
            SCHEDULER="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# Check if the necessary variables are set
if [[ -z "$SCHEDULER" ]]; then
    usage
fi

# Create the scheduler directory if it doesn't exist
if [[ ! -d "$SCHEDULER" ]]; then
    mkdir -p "$SCHEDULER"
fi

# Get the current UNIX timestamp
TIME=$(date +%s)

# Define the list of experiments
experiments=("fillseq" "fillsync" "overwrite" "readrandom" "seekrandom" "fillrandom")

# Run on experiments
for experiment in "${experiments[@]}"; do
    # Run commands in parallel
    for i in {1..10}; do
        /home/dedongx/rocksdb/db_bench --benchmarks="$experiment" "--db=/mnt/test_disk_$i" --num=4000000 --threads=16 --duration=50 --key_size=32 --value_size=1024 --batch_size=16 --write_buffer_size=1073741824 --max_write_buffer_number=50 --cache_size=0 >> "${SCHEDULER}/${TIME}_db_bench_${i}.log" &
    done

    # Wait for all background processes to finish
    wait

    # Output experiment finish signal
    echo "db_bench $experiment have completed."

    # Restore controller by adding sleep
    sleep 60
done

echo "All db_bench benchmarks have completed."
