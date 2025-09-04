#!/bin/bash

# Array of tests
# TESTS=("workloada" "workloadb" "workloadc" "workloadd" "workloade" "workloadf")
TESTS=("workloada")

# Run the previous script for each test
for TEST in "${TESTS[@]}"; do
    echo "Loading $TEST workloads..."
    ./load_ycsb_workloads.sh -w "$TEST"
    echo "$TEST workload load done"
done

echo "All workloads have been loaded to all 10 disks."
