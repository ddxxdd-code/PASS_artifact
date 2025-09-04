#!/usr/bin/env python3
"""
Read latency data from CSV with columns: system, background_jobs, p99_latency.
Normalize all latencies against spdk_static at the same background_jobs,
output the normalized table to CSV, and plot.
"""

import pandas as pd
import matplotlib.pyplot as plt
import math
import argparse

def main():
    parser = argparse.ArgumentParser(description="Plot normalized latency vs background jobs")
    parser.add_argument(
        "--csv",
        type=str,
        default="latency_data_ref.csv",
        help="Input CSV file with columns: system, background_jobs, p99_latency"
    )
    parser.add_argument(
        "--out-csv",
        type=str,
        default="latency_data_normalized.csv",
        help="Output CSV file with normalized latency results"
    )
    args = parser.parse_args()

    # ---------------- Plot Style ----------------
    plt.rcParams.update({
        "font.size":       12,
        "axes.titlesize":  16,
        "axes.labelsize":  16,
        "xtick.labelsize": 16,
        "ytick.labelsize": 16,
        "legend.fontsize": 12,
    })

    # ---------------- Load CSV ----------------
    df = pd.read_csv(args.csv)

    # Extract baseline (spdk_static) latencies
    baseline = (
        df[df["system"].str.lower() == "spdk_static"]
        .set_index("background_jobs")["p99_latency"]
    )

    # Normalize against spdk_static baseline
    df["norm_latency"] = df.apply(
        lambda row: row["p99_latency"] / baseline.get(row["background_jobs"], math.nan),
        axis=1
    )

    # Save normalized data
    df.to_csv(args.out_csv, index=False)
    print(f"Normalized results written to {args.out_csv}")

    # ---------------- Plot ----------------
    styles = {
        "spdk_dynamic": dict(marker="o", linestyle="-"),
        "linux":        dict(marker="^", linestyle=":"),
        "spdk_static":  dict(marker="s", linestyle="--"),
    }

    plt.figure(figsize=(8, 5))

    for system, g in df.groupby("system"):
        if system.lower() == "spdk_static":
            continue  # skip baseline in plot (it's always 1.0)
        x = g["background_jobs"] / 8 * 100  # utilization %
        y = g["norm_latency"]
        plt.plot(x, y, label=system, **styles.get(system.lower(), {}))

    plt.xlabel("Background Machine Utilization (%)")
    plt.ylabel("Normalized Foreground P99 Latency")
    plt.ylim(1, None)
    plt.grid(True, ls="--", lw=0.5)
    plt.legend()
    plt.tight_layout()

    plt.savefig("fig1_foreground_p99_latency_normalized.pdf", dpi=300)


if __name__ == "__main__":
    main()
