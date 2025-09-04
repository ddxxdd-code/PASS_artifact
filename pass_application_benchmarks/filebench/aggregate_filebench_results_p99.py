#!/usr/bin/env python3
import os
import argparse
import csv
import re
import statistics as st

# ────────────────────────── Helpers ────────────────────────── #

def parse_log_file(filepath):
    """
    Parse a Filebench log and return:
        throughput (ops/s, float or None),
        p99_read   (µs,    float or None),
        p99_write  (µs,    float or None)
    """
    thr = rd_p99 = wr_p99 = None

    thr_pat = re.compile(r"IO Summary.*?([\d.]+)\s+ops/s")
    p99_pat = re.compile(r"#\[.*?p99\s*=\s*([\d.]+)")
    section = None                       # Track Read / Write blocks

    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            # Throughput
            if thr is None:
                m = thr_pat.search(line)
                if m:
                    thr = float(m.group(1))

            # Section starts
            if "Read Latency" in line:
                section = "read"
            elif "Write Latency" in line:
                section = "write"

            # p99 inside the summary comment
            if section and "#[p95" in line:          # p99 appears in same comment block
                m = p99_pat.search(line)
                if m:
                    if section == "read":
                        rd_p99 = float(m.group(1))
                    else:
                        wr_p99 = float(m.group(1))
                    section = None  # Done with this latency block

            if thr is not None and rd_p99 is not None and wr_p99 is not None:
                break

    return thr, rd_p99, wr_p99

# ────────────────── Aggregation / CSV output ────────────────── #

def aggregate_results(scheduler, powercap, workload):
    """
    Sum throughput and average p99 latencies across the latest log
    for each disk. Results are written to
        {scheduler}_{powercap}/{scheduler}_{workload}_aggregated_throughput.csv
    """
    directory = f"{scheduler}_{powercap}"
    if not os.path.isdir(directory):
        print(f"[WARN] Directory '{directory}' does not exist.")
        return

    out_dir = directory
    os.makedirs(out_dir, exist_ok=True)
    out_csv = os.path.join(
        out_dir, f"{scheduler}_{workload}_aggregated_throughput.csv"
    )

    total_thr = 0.0
    read_p99s, write_p99s = [], []

    # Pick newest log per disk
    latest = {}
    for disk in range(1, 11):
        suffix = f"_{workload}_{disk}.log"
        for fn in os.listdir(directory):
            if fn.endswith(suffix):
                ts = fn.split("_")[0]          # assumes leading timestamp
                if disk not in latest or ts > latest[disk][0]:
                    latest[disk] = (ts, fn)

    # Parse & aggregate
    for ts, fn in latest.values():
        thr, rp99, wp99 = parse_log_file(os.path.join(directory, fn))
        if thr is None:
            print(f"[SKIP] '{fn}' missing throughput.")
            continue
        total_thr += thr
        if rp99 is not None:
            read_p99s.append(rp99)
        if wp99 is not None:
            write_p99s.append(wp99)

    # Average latencies (NaN if no data)
    avg_rd_p99 = st.mean(read_p99s)  if read_p99s  else float("nan")
    avg_wr_p99 = st.mean(write_p99s) if write_p99s else float("nan")

    # Write CSV
    with open(out_csv, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "method", "powercap", "workload",
            "total throughput (ops/s)",
            "avg read p99 (µs)", "avg write p99 (µs)"
        ])
        w.writerow([
            scheduler, powercap, workload,
            total_thr, avg_rd_p99, avg_wr_p99
        ])

    print(f"[OK] Aggregated data saved → {out_csv}")

# ────────────────────────── CLI entry ────────────────────────── #

def main():
    ap = argparse.ArgumentParser(
        description="Aggregate Filebench throughput & p99 latency.")
    ap.add_argument("-s", "--scheduler", required=True)
    ap.add_argument("-c", "--powercap",  required=True)
    ap.add_argument("-w", "--workload",  required=True)
    args = ap.parse_args()
    aggregate_results(args.scheduler, args.powercap, args.workload)

if __name__ == "__main__":
    main()
