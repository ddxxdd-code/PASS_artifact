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

# Run commands in parallel
for i in {1..10}; do
    # ../rocksdb/db_bench --benchmarks="fillseq,fillrandom,overwrite,readseq,readrandom,seekrandom" "-db=/mnt/test_disk_$i" --num=10000000 --threads=16 > "${SCHEDULER}/${TIME}_db_bench_${i}.log" &
    # ../rocksdb/db_bench --benchmarks="fillseq,fillrandom,overwrite,readseq,readrandom,seekrandom" "--db=/mnt/test_disk_$i" --num=4000000 --threads=16 --duration=50 --key_size=32 --value_size=1024 --batch_size=16 --write_buffer_size=1073741824 --max_write_buffer_number=50 > "${SCHEDULER}/${TIME}_db_bench_${i}.log" &
    ../rocksdb/db_bench --benchmarks="fillseq,fillsync,fillrandom,overwrite,readrandom,seekrandom" "--db=/mnt/test_disk_$i" --num=4000000 --threads=16 --duration=60 --key_size=32 --value_size=1024 --batch_size=16 --write_buffer_size=1073741824 --max_write_buffer_number=50 --cache_size=0 > "${SCHEDULER}/${TIME}_db_bench_${i}.log" &
    # ../rocksdb/db_bench --benchmarks="readrandom,seekrandom" "--db=/mnt/test_disk_$i" --num=4000000 --threads=16 --duration=50 --key_size=32 --value_size=1024 --batch_size=16 --write_buffer_size=1073741824 --max_write_buffer_number=50 > "${SCHEDULER}/${TIME}_db_bench_${i}.log" &
    # ../rocksdb/db_bench --benchmarks="fillsync,fillrandom,overwrite" "--db=/mnt/test_disk_$i" --num=4000000 --threads=16 --duration=50 --key_size=32 --value_size=1024 --batch_size=16 --write_buffer_size=1073741824 --max_write_buffer_number=50 > "${SCHEDULER}/${TIME}_db_bench_${i}.log" &
done

# Wait for all background processes to finish
wait

echo "All db_bench commands have completed."
