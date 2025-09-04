#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 -t|--test <test> -s|--scheduler <scheduler>"
    exit 1
}

# Parse input arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test)
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
    filebench -f "${TEST}_${i}.f" > "${SCHEDULER}/${TIME}_${TEST}_${i}.log" &
done

# Wait for all background processes to finish
wait

echo "All filebench commands have completed."
