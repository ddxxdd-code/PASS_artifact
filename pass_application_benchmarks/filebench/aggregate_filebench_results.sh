#!/bin/bash

# Check for required arguments
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 -s <scheduler> -c <powercap>"
    exit 1
fi

# Parse arguments
while getopts "s:c:" opt; do
    case $opt in
        s) scheduler="$OPTARG" ;;
        c) powercap="$OPTARG" ;;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Define the workloads
workloads=("varmail" "webserver" "fileserver")

# Run the Python script for each workload
for workload in "${workloads[@]}"; do
    echo "Running aggregation for scheduler=$scheduler, powercap=$powercap, workload=$workload"
    python3 aggregate_filebench_results_p99.py -s "$scheduler" -c "$powercap" -w "$workload"
    if [ $? -ne 0 ]; then
        echo "Error: Aggregation failed for workload $workload"
        exit 1
    fi
done

echo "Aggregation completed for all workloads."
