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

# Check if the scheduler is set
if [[ -z "$SCHEDULER" ]]; then
    usage
fi

# Warmup power control
# ./run_filebench_warmup.sh -t varmail

# Array of tests
# TESTS=("varmail" "webserver" "fileserver")
TESTS=("varmail")
# TESTS=("webserver")
# TESTS=("fileserver")

# Run the previous script for each test
for TEST in "${TESTS[@]}"; do
    echo "Running $TEST experiments..."
    ./run_filebench_tests.sh -t "$TEST" -s "$SCHEDULER"
    echo "$TEST experiments done"
    sleep 20
done

echo "All tests have been executed with scheduler: $SCHEDULER."
