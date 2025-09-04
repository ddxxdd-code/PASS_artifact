#!/usr/bin/env python3
"""
Plot foreground p99 latency versus power budget from CSV.

Input CSV columns:
  system,power,p99_latency_usecs
    - system: 'pass' or 'thunderbolt'
    - power: integer watts
    - p99_latency_usecs: integer latency in µs
"""

import argparse
import csv
from collections import defaultdict
import matplotlib.pyplot as plt

# Map system names in CSV to legend labels
SYSTEM_LABEL = {
    "pass": "PASS (Ours)",
    "thunderbolt": "SPDK + Thunderbolt",
}

def parse_args():
    ap = argparse.ArgumentParser(description="Plot foreground latency vs power")
    ap.add_argument("csv_path", nargs="?", default="foreground_latency_ref.csv",
                    help="CSV with columns system,power,p99_latency_usecs")
    ap.add_argument("-o", "--out", default="bursty_foreground.pdf",
                    help="Output PDF filename")
    return ap.parse_args()

def load_data(csv_path):
    data = defaultdict(dict)
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            sys_raw = (row["system"] or "").strip().lower()
            if sys_raw not in SYSTEM_LABEL:
                continue
            label = SYSTEM_LABEL[sys_raw]
            try:
                power = int(row["power"])
                latency = float(row["p99_latency_usecs"])
            except Exception:
                continue
            data[label][power] = latency
    return data

def main():
    args = parse_args()
    data = load_data(args.csv_path)

    if not data:
        raise SystemExit("No valid rows parsed from CSV.")

    powers = sorted({p for sys_data in data.values() for p in sys_data}, reverse=True)

    styles = {
        "PASS (Ours)":          dict(marker="s",  linestyle="--", color="tab:orange"),
        "SPDK + Thunderbolt":   dict(marker="D",  linestyle="-.", color="tab:green"),
    }

    plt.figure(figsize=(8, 5))

    for label, sys_data in data.items():
        x = [p for p in powers if p in sys_data]
        y = [sys_data[p] for p in x]
        if not x:
            continue
        plt.plot(x, y, label=label, **styles.get(label, {}))

    plt.xlabel("Power (W)")
    plt.ylabel("Foreground p99 Latency (µs)")
    plt.title("Foreground p99 Latency vs. Power Budget (Log Scale)")
    plt.yscale("log")
    plt.grid(True, which="both", ls="--", lw=0.5)
    plt.legend()
    plt.tight_layout()
    plt.savefig(args.out, dpi=300)
    print(f"Wrote {args.out}")

if __name__ == "__main__":
    main()
