#!/usr/bin/env python3
"""
Plot foreground-throughput versus power budget from a CSV.

Input CSV columns (no header order requirement):
  system,power,throughput
    - system: 'pass' or 'thunderbolt'
    - power: integer watts, e.g., 270, 300, 330, 380, 440
    - throughput: float in GiB/s

The script converts throughput GiB/s → MiB/s and plots one line per system.
"""

import argparse
import csv
from collections import defaultdict
import matplotlib.pyplot as plt

# Map CSV "system" values to nicer legend labels
SYSTEM_LABEL = {
    "pass": "PASS (Ours)",
    "thunderbolt": "SPDK + Thunderbolt",
}

def parse_args():
    ap = argparse.ArgumentParser(description="Plot throughput (MiB/s) vs power from CSV")
    ap.add_argument("csv_path", nargs="?", default="background_throughput_ref.csv", help="Input CSV with columns: system,power,throughput (GiB/s)")
    ap.add_argument("-o", "--out", default="bursty_background.pdf", help="Output PDF filename")
    return ap.parse_args()

def load_data(csv_path):
    """
    Returns: dict[label] -> dict[power:int] -> throughput_mib: float
    """
    data = defaultdict(dict)
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        required = {"system", "power", "throughput"}
        missing = required - set(h.strip().lower() for h in reader.fieldnames or [])
        if missing:
            raise ValueError(f"CSV missing required columns: {sorted(list(missing))}")

        for row in reader:
            sys_raw = (row["system"] or "").strip().lower()
            if sys_raw not in SYSTEM_LABEL:
                # Skip unknown systems silently; add another label mapping if needed
                continue
            label = SYSTEM_LABEL[sys_raw]

            try:
                power = int(str(row["power"]).strip())
            except Exception:
                continue  # skip bad rows

            try:
                gib_s = float(str(row["throughput"]).strip())
            except Exception:
                continue

            mib_s = gib_s * 1024.0
            data[label][power] = mib_s
    return data

def main():
    args = parse_args()
    data = load_data(args.csv_path)

    if not data:
        raise SystemExit("No valid rows parsed from CSV (check system/power/throughput values).")

    # Union of all power levels, sorted high→low for nicer ordering on the x-axis
    powers = sorted({p for sys_data in data.values() for p in sys_data}, reverse=True)

    # Optional: per-system styles (safe to drop if you prefer defaults)
    styles = {
        "PASS (Ours)":          dict(marker="s",  linestyle="--"),
        "SPDK + Thunderbolt":   dict(marker="D",  linestyle="-."),
    }

    plt.figure(figsize=(8, 5))

    for label, sys_data in data.items():
        x = [p for p in powers if p in sys_data]
        y = [sys_data[p] for p in x]
        if not x:
            continue
        plt.plot(x, y, label=label, **styles.get(label, {}))

    plt.xlabel("Power (W)")
    plt.ylabel("Throughput (MiB/s)")
    plt.title("Background Throughput vs. Power Budget")
    plt.grid(True, ls="--", lw=0.5)
    plt.legend()
    plt.tight_layout()
    plt.savefig(args.out, dpi=300)
    print(f"Wrote {args.out}")

if __name__ == "__main__":
    main()
