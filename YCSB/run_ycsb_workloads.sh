#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 -w|--workload <test> -s|--scheduler <scheduler>"
    exit 1
}

# Parse input arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--workload)
            TEST="$2"
            shift 2
            ;;
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
if [[ -z "$SCHEDULER" || -z "$TEST" ]]; then
    usage
fi

# Create the scheduler directory if it doesn't exist
if [[ ! -d "$SCHEDULER" ]]; then
    mkdir -p "$SCHEDULER"
fi

# Get the current UNIX timestamp
TIME=$(date +%s)

# Run commands in parallel
for i in {1..10}; do
    ./bin/ycsb run rocksdb -s -P "workloads/${TEST}" -p "rocksdb.dir=/mnt/test_disk_${i}" -p rocksdb.optionsfile=ycsb_rocksdb_config.ini -p recordcount=100000000 -p operationcount=200000000 -p maxexecutiontime=180 -threads 64 > "${SCHEDULER}/${TIME}_${TEST}_${i}.log" &
done

# Wait for all background processes to finish
wait

echo "All db_bench commands have completed."
