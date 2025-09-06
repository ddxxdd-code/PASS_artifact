#!/usr/bin/env python3
import os
import re
import csv
import argparse
from statistics import mean

# ───────────────────────── Parsing ───────────────────────── #

WORKLOADS = [
    "fillseq", "fillsync", "fillrandom", "overwrite",
    "readrandom", "seekrandom"
]

def parse_log_file(file_path):
    """
    Return a dict: { workload: (throughput_ops, p99_latency_us) }
    Any missing value is returned as None.
    """
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()

    out = {wk: (None, None) for wk in WORKLOADS}

    for wk in WORKLOADS:
        # 1) throughput (ops/sec)
        m_thr = re.search(rf"{wk}\s*:.*?(\d+)\s+ops/sec", text, re.I | re.S)
        thr   = int(m_thr.group(1)) if m_thr else None

        # 2) P99 latency (µs)
        m_p99 = re.search(rf"{wk}.*?Percentiles:.*?P99:\s*([0-9.]+)", text, re.I | re.S)
        p99   = float(m_p99.group(1)) if m_p99 else None

        out[wk] = (thr, p99)
    return out

# ───────────────────────── Processing ───────────────────────── #

def process_logs(method, powercap):
    directory = f"{method}_{powercap}"
    if not os.path.isdir(directory):
        print(f"Directory '{directory}' does not exist.")
        return

    # Find the newest timestamp among files like: 1684284962_db_bench_3.log
    ts_set = {
        m.group(1)
        for m in (re.match(r"(\d+)_db_bench_\d+\.log$", fname) for fname in os.listdir(directory))
        if m
    }
    if not ts_set:
        print(f"No log files in '{directory}'.")
        return
    latest_ts = max(ts_set)  # timestamps are numeric strings; max() is fine

    # Parse every disk log that exists
    per_disk = []
    for disk in range(1, 11):
        fpath = os.path.join(directory, f"{latest_ts}_db_bench_{disk}.log")
        if os.path.exists(fpath):
            per_disk.append(parse_log_file(fpath))

    if not per_disk:
        print(f"No valid logs for timestamp '{latest_ts}' in '{directory}'.")
        return

    # Aggregate across disks
    agg_thr = {wk: 0  for wk in WORKLOADS}
    agg_p99 = {wk: [] for wk in WORKLOADS}

    for disk_dict in per_disk:
        for wk, (thr, p99) in disk_dict.items():
            if thr is not None:
                agg_thr[wk] += thr
            if p99 is not None:
                agg_p99[wk].append(p99)

    avg_p99 = {wk: (mean(vals) if vals else None) for wk, vals in agg_p99.items()}

    # ── write CSV named <system>_db_bench_aggregated_metrics.csv ──
    out_csv = os.path.join(directory, f"{method}_db_bench_aggregated_metrics.csv")
    with open(out_csv, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["method", "powercap", "workload", "throughput (ops/s)", "p99 latency (µs)"])
        for wk in WORKLOADS:
            w.writerow([
                method,
                powercap,
                wk,
                agg_thr[wk],
                f"{avg_p99[wk]:.2f}" if avg_p99[wk] is not None else ""
            ])

    print(f"Aggregated metrics written → {out_csv}")

# ────────────────────────── CLI ────────────────────────── #

def main():
    ap = argparse.ArgumentParser(description="Aggregate db_bench throughput & p99 latency.")
    ap.add_argument("-s", "--scheduler", required=True, help="Scheduler/method name (system).")
    ap.add_argument("-c", "--powercap",  required=True, help="Power cap value (e.g., 360, unlimited).")
    args = ap.parse_args()
    process_logs(args.scheduler, args.powercap)

if __name__ == "__main__":
    main()
