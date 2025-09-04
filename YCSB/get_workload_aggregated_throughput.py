import argparse
import os
import re
import csv

def parse_log_file(file_path):
    """
    Parse a log file to extract the overall throughput.
    """
    with open(file_path, 'r') as file:
        for line in file:
            if "[OVERALL], Throughput(ops/sec)" in line:
                throughput = float(line.split(",")[2].strip())
                return throughput
    return None

def collect_throughput(directory, workload):
    """
    Collect throughput data for the latest timestamp logs under the specified directory and workload.
    """
    log_files = [f for f in os.listdir(directory) if f.endswith(".log")]
    
    # Extract timestamps and find the latest one
    timestamp_pattern = re.compile(r"^(\d+)_{}_.*\.log$".format(workload))
    timestamps = {int(timestamp_pattern.match(f).group(1)) for f in log_files if timestamp_pattern.match(f)}
    
    if not timestamps:
        print("No valid log files found for workload '{}'.".format(workload))
        return []
    
    latest_timestamp = max(timestamps)
    print(f"Latest timestamp identified: {latest_timestamp}")
    
    # Collect throughput for the latest timestamp
    results = []
    for disk_num in range(1, 11):  # From disk 1 to 10
        log_file = f"{latest_timestamp}_{workload}_{disk_num}.log"
        log_path = os.path.join(directory, log_file)
        if os.path.exists(log_path):
            throughput = parse_log_file(log_path)
            if throughput is not None:
                results.append((latest_timestamp, disk_num, throughput))
    return results

def aggregate_throughput_to_csv(directory, method, powercap, workload, results):
    """
    Aggregate throughput results and save to a CSV file.
    """
    if not results:
        print("No results found.")
        return

    # Aggregate results by summing throughput
    aggregated_throughput = sum(result[2] for result in results)
    timestamp = results[0][0]  # Assuming the same timestamp for all results

    # Prepare CSV file path
    output_file = os.path.join(directory, f"{timestamp}_{workload}_aggregated_throughput.csv")
    
    # Write to CSV
    with open(output_file, 'w', newline='') as csvfile:
        csvwriter = csv.writer(csvfile)
        csvwriter.writerow(["method", "powercap", "workload", "throughput (ops/s)"])
        csvwriter.writerow([method, powercap, workload, aggregated_throughput])
    
    print(f"Aggregated throughput saved to: {output_file}")

def main():
    parser = argparse.ArgumentParser(description="Retrieve and aggregate throughput data from YCSB logs.")
    parser.add_argument('-m', '--method', required=True, help="Method (e.g., cpu_only, disk_only, dynamic_scheduler, dynamic_tuned)")
    parser.add_argument('-c', '--powercap', required=True, help="Power cap (e.g., 500, 410, 360)")
    parser.add_argument('-w', '--workload', required=True, help="Workload name (e.g., workloada, workloadb)")
    args = parser.parse_args()

    method = args.method
    powercap = args.powercap
    workload = args.workload
    directory = f"{method}_{powercap}"

    if not os.path.isdir(directory):
        print(f"Directory '{directory}' not found.")
        return

    results = collect_throughput(directory, workload)
    aggregate_throughput_to_csv(directory, method, powercap, workload, results)

if __name__ == "__main__":
    main()
