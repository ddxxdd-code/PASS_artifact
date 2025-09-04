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
        *)
            usage
            ;;
    esac
done

# Check if the necessary variables are set
if [[ -z "$TEST" ]]; then
    usage
fi

# Get the current UNIX timestamp
TIME=$(date +%s)

# Run commands in parallel
for i in {1..10}; do
    ./bin/ycsb load rocksdb -s -P "workloads/${TEST}" -p "rocksdb.dir=/mnt/test_disk_${i}" -p rocksdb.optionsfile=ycsb_rocksdb_config.ini -p recordcount=100000000 -p operationcount=200000000> /dev/null &
done

wait

echo "All ycsb workload $TEST have loaded."
