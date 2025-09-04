import os
import argparse
import pandas as pd

def merge_csv_files(method, powercap):
    """
    Merges all `<timestamp>_<workload>_aggregated_throughput.csv` files in the specified directory into one CSV file.
    """
    directory = f"{method}_{powercap}"
    if not os.path.isdir(directory):
        print(f"Directory '{directory}' not found.")
        return
    
    # List all CSV files in the directory
    csv_files = [
        os.path.join(directory, f) for f in os.listdir(directory)
        if f.endswith("_aggregated_throughput.csv")
    ]
    
    if not csv_files:
        print(f"No aggregated throughput CSV files found in '{directory}'.")
        return
    
    # Read and concatenate all CSV files
    dataframes = []
    for csv_file in csv_files:
        print(f"Processing file: {csv_file}")
        df = pd.read_csv(csv_file)
        dataframes.append(df)
    
    # Merge all dataframes
    merged_df = pd.concat(dataframes, ignore_index=True)

    # Save the merged dataframe to a new CSV file
    output_file = os.path.join(directory, f"{method}_{powercap}_merged_throughput.csv")
    merged_df.to_csv(output_file, index=False)
    print(f"Merged CSV file saved to: {output_file}")

def main():
    parser = argparse.ArgumentParser(description="Merge aggregated throughput CSV files.")
    parser.add_argument('-m', '--method', required=True, help="Method (e.g., cpu_only, disk_only, dynamic_scheduler, dynamic_tuned)")
    parser.add_argument('-c', '--powercap', required=True, help="Power cap (e.g., 500, 410, 360)")
    args = parser.parse_args()

    merge_csv_files(args.method, args.powercap)

if __name__ == "__main__":
    main()
