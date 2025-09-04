import os
import argparse
import csv
import re

def parse_log_file(filepath):
    """
    Parse the log file to extract the total overall throughput.
    Returns the throughput value in ops/s or None if the file is incomplete or invalid.
    """
    try:
        with open(filepath, 'r') as file:
            lines = file.readlines()
        
        # Check if the file contains the necessary IO Summary
        for line in lines:
            if "IO Summary" in line:
                match = re.search(r"(\d+\.?\d*)\s+ops/s", line)
                if match:
                    return float(match.group(1))
        return None
    except Exception as e:
        print(f"Error reading file {filepath}: {e}")
        return None

def aggregate_results(scheduler, powercap, workload):
    """
    Collect throughput data for the given scheduler, powercap, and workload,
    compute the total throughput across all disks, and save to a CSV.
    """
    directory = f"{scheduler}_{powercap}"
    if not os.path.exists(directory):
        print(f"Directory {directory} does not exist.")
        return

    output_directory = f"{scheduler}_{powercap}"
    os.makedirs(output_directory, exist_ok=True)
    output_file = os.path.join(output_directory, f"{scheduler}_{workload}_aggregated_throughput.csv")

    total_throughput = 0
    latest_files = {}

    # Identify the latest file for each disk number
    for disk_num in range(1, 11):
        pattern = f"_{workload}_{disk_num}.log"
        files = [f for f in os.listdir(directory) if f.endswith(pattern)]
        
        for file in files:
            timestamp = file.split("_")[0]
            if disk_num not in latest_files or timestamp > latest_files[disk_num][0]:
                latest_files[disk_num] = (timestamp, file)

    # Process only the latest files and calculate total throughput
    for _, (timestamp, file) in latest_files.items():
        filepath = os.path.join(directory, file)
        throughput = parse_log_file(filepath)
        if throughput is not None:
            total_throughput += throughput
        else:
            print(f"Skipping invalid or incomplete log file: {file}")

    # Write the aggregated total throughput to the CSV
    with open(output_file, 'w', newline='') as csvfile:
        csv_writer = csv.writer(csvfile)
        csv_writer.writerow(["method", "powercap", "workload", "total throughput (ops/s)"])
        csv_writer.writerow([scheduler, powercap, workload, total_throughput])
    
    print(f"Aggregated throughput data saved to {output_file}")

def main():
    parser = argparse.ArgumentParser(description="Aggregate throughput data from Filebench results.")
    parser.add_argument("-s", "--scheduler", required=True, help="Scheduler method (e.g., some_method).")
    parser.add_argument("-c", "--powercap", required=True, help="Powercap (e.g., unlimited, 500).")
    parser.add_argument("-w", "--workload", required=True, help="Workload name (e.g., varmail, webserver).")
    
    args = parser.parse_args()
    aggregate_results(args.scheduler, args.powercap, args.workload)

if __name__ == "__main__":
    main()
