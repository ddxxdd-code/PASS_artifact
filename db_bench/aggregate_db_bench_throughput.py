import os
import re
import csv
import argparse
from pathlib import Path

# Function to parse the throughput from a log file
def parse_throughput(file_path):
    with open(file_path, 'r') as file:
        content = file.read()

    # Dictionary to hold the throughput values for each workload
    workloads = ["fillseq", "fillsync", "fillrandom", "overwrite", "readrandom", "seekrandom"]
    throughput_data = {workload: None for workload in workloads}

    for workload in workloads:
        # Regex to find throughput values (ops/sec)
        match = re.search(rf"{workload}\s*:\s*.+?(\d+)\s+ops/sec", content)
        if match:
            throughput_data[workload] = int(match.group(1))
    
    return throughput_data

# Function to process the logs and aggregate the data
def process_logs(method, powercap):
    directory = f"{method}_{powercap}"
    if not os.path.exists(directory):
        print(f"Directory '{directory}' does not exist.")
        return
    
    # Find the latest timestamp
    timestamps = set()
    for file in os.listdir(directory):
        match = re.match(r"(\d+)_db_bench_\d+.log", file)
        if match:
            timestamps.add(match.group(1))
    
    if not timestamps:
        print(f"No log files found in directory '{directory}'.")
        return
    
    latest_timestamp = max(timestamps)

    # Initialize aggregated data
    aggregated_data = []
    for disk_num in range(1, 11):
        log_file = os.path.join(directory, f"{latest_timestamp}_db_bench_{disk_num}.log")
        if os.path.exists(log_file):
            throughput_data = parse_throughput(log_file)
            aggregated_data.append(throughput_data)

    # Calculate aggregated throughput for each workload
    if not aggregated_data:
        print(f"No valid logs found in directory '{directory}' for timestamp '{latest_timestamp}'.")
        return

    # Aggregate the throughput values
    aggregated_throughput = {workload: 0 for workload in aggregated_data[0]}
    for data in aggregated_data:
        for workload, throughput in data.items():
            if throughput:
                aggregated_throughput[workload] += throughput

    # Write all aggregated throughput data to a single CSV file
    output_file = os.path.join(directory, f"{latest_timestamp}_aggregated_throughput.csv")
    with open(output_file, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["method", "powercap", "workload", "throughput (ops/s)"])
        for workload, throughput in aggregated_throughput.items():
            writer.writerow([method, powercap, workload, throughput])
    
    print(f"Aggregated throughput written to '{output_file}'.")

# Main function to handle argument parsing and processing
def main():
    parser = argparse.ArgumentParser(description="Process db_bench result logs.")
    parser.add_argument("-s", "--scheduler", required=True, help="Scheduler method (e.g., 'method_name').")
    parser.add_argument("-c", "--powercap", required=True, help="Power cap value (e.g., 'unlimited', '500').")
    args = parser.parse_args()

    process_logs(args.scheduler, args.powercap)

if __name__ == "__main__":
    main()
