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
# for i in {1..10}; do
    # ../rocksdb/db_bench --benchmarks="fillseq,fillrandom,overwrite,readseq,readrandom,seekrandom" "-db=/mnt/test_disk_$i" --num=10000000 --threads=16 > "${SCHEDULER}/${TIME}_db_bench_${i}.log" &
    # ../rocksdb/db_bench --benchmarks="fillrandom" "--db=/mnt/test_disk_$i" --num=5000000 --threads=16 --duration=60 --key_size=48 --value_size=100 --batch_size=32 --write_buffer_size=1073741824 --max_write_buffer_number=20 --cache_size=0 > "${SCHEDULER}/${TIME}_db_bench_seq_fill_${i}.log" &
    # ../rocksdb/db_bench --benchmarks="overwrite" "--db=/mnt/test_disk_$i" --compression_type=none --num=5000000 --threads=1 --duration=60 --key_size=48 --value_size=4096 --batch_size=16 --write_buffer_size=4194304 --min_write_buffer_number_to_merge=1 --max_write_buffer_number=2 --cache_size=0 --disable_wal=false --sync=true> "${SCHEDULER}/${TIME}_db_bench_seq_fill_${i}.log" &
# done
for j in {1..2}; do
    for i in {1..10}; do
        # ../rocksdb/db_bench --benchmarks="fillseq,fillrandom,overwrite,readseq,readrandom,seekrandom" "-db=/mnt/test_disk_$i" --num=10000000 --threads=16 > "${SCHEDULER}/${TIME}_db_bench_${i}.log" &
        # ../rocksdb/db_bench --benchmarks="fillseq,fillrandom,overwrite,readseq,readrandom,seekrandom" "--db=/mnt/test_disk_$i" --num=4000000 --threads=16 --duration=50 --key_size=32 --value_size=1024 --batch_size=16 --write_buffer_size=1073741824 --max_write_buffer_number=50 > "${SCHEDULER}/${TIME}_db_bench_${i}.log" &
        ../rocksdb/db_bench \
        --benchmarks="mixgraph,stats" \
        "--db=/mnt/test_disk_$i" \
        -use_direct_io_for_flush_and_compaction=true \
        -use_direct_reads=true \
        --compression_type=none \
        -cache_size=4096 \
        -keyrange_dist_a=14.18 \
        -keyrange_dist_b=-2.917 \
        -keyrange_dist_c=0.0164 \
        -keyrange_dist_d=-0.08082 \
        -keyrange_num=30 \
        -value_k=0.2615 \
        -value_sigma=25.45 \
        -iter_k=2.517 \
        -iter_sigma=14.236 \
        -mix_get_ratio=0.85 \
        -mix_put_ratio=0.14 \
        -mix_seek_ratio=0.01 \
        -sine_mix_rate_interval_milliseconds=100 \
        -sine_a=700000 \
        -sine_b=20 \
        -sine_d=450000 \
        --perf_level=2 \
        --threads=16 \
        --duration=12 \
        --statistics \
        -reads=4200000 \
        -num=50000000 \
        -key_size=48 \
        >> "${SCHEDULER}/${TIME}_zippy_db_${i}.log" &
    done
    # sleep 10
    sleep 15
done

# Wait for all background processes to finish
wait

echo "All db_bench commands have completed."
