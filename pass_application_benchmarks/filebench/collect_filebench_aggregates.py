#!/usr/bin/env python3
"""
Collect all <system>_<experiment>_aggregated_throughput.csv files from directories
named <system>_<power> and merge them into a single CSV.

Each input CSV has exactly one data row with this header:
  method,powercap,workload,total throughput (ops/s),avg read p99 (µs),avg write p99 (µs)

Usage examples:
  # Defaults: PASS=500, TB=500, LINUX=500
  python3 collect_filebench_aggregates.py

  # Explicit caps
  python3 collect_filebench_aggregates.py \
      --pass-caps 500 265 300 350 400 \
      --tb-caps 500 265 300 350 400 \
      --linux-caps 500 \
      --out filebench_aggregated_all.csv
"""
import argparse
import csv
import sys
from pathlib import Path
from typing import List

REQUIRED_COLS = [
    "method",
    "powercap",
    "workload",
    "total throughput (ops/s)",
    "avg read p99 (µs)",
    "avg write p99 (µs)",
]

def parse_args():
    ap = argparse.ArgumentParser(description="Merge per-dir aggregated throughput CSVs into one file.")
    ap.add_argument("--out", default="filebench_combined.csv",
                    help="Output CSV path (default: filebench_combined.csv)")
    ap.add_argument("--pass-caps", nargs="+", type=int, default=[500],
                    help="List of PASS power caps (e.g., 500 265 300 350 400)")
    ap.add_argument("--tb-caps", nargs="+", type=int, default=[500],
                    help="List of Thunderbolt power caps (e.g., 500 265 300 350 400)")
    ap.add_argument("--linux-caps", nargs="+", type=int, default=[500],
                    help="List of Linux power caps (e.g., 500)")
    ap.add_argument("--root", default=".", help="Root directory to scan (default: current dir)")
    return ap.parse_args()

def find_csvs_for(system: str, cap: int, root: Path) -> List[Path]:
    """Return all *_aggregated_throughput.csv inside <system>_<cap>/"""
    d = root / f"{system}_{cap}"
    if not d.is_dir():
        return []
    return sorted(d.glob("*_aggregated_throughput.csv"))

def validate_header(header: List[str]) -> bool:
    return [h.strip() for h in header] == REQUIRED_COLS

def main():
    args = parse_args()
    root = Path(args.root).resolve()
    out_path = Path(args.out)

    plan = [
        ("pass", args.pass_caps),
        ("thunderbolt", args.tb_caps),
        ("linux", args.linux_caps),
    ]

    rows = []
    missing_dirs = []
    empty_dirs = []
    bad_headers = []

    for system, caps in plan:
        for cap in caps:
            csv_paths = find_csvs_for(system, cap, root)
            if not (root / f"{system}_{cap}").exists():
                missing_dirs.append(f"{system}_{cap}")
                continue
            if not csv_paths:
                empty_dirs.append(f"{system}_{cap}")
                continue

            for p in csv_paths:
                with p.open("r", newline="") as f:
                    reader = csv.reader(f)
                    try:
                        header = next(reader)
                    except StopIteration:
                        bad_headers.append(str(p))
                        continue

                    if not validate_header(header):
                        bad_headers.append(str(p))
                        continue

                    try:
                        row = next(reader)  # exactly one data row per file
                    except StopIteration:
                        # no data row
                        continue

                    # Keep exactly the required columns/order
                    rows.append(row)

    # Write output
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(REQUIRED_COLS)
        writer.writerows(rows)

    # Stderr diagnostics
    print(f"[collect] wrote {len(rows)} rows → {out_path}", file=sys.stderr)
    if missing_dirs:
        print(f"[collect] missing dirs ({len(missing_dirs)}): {', '.join(missing_dirs)}", file=sys.stderr)
    if empty_dirs:
        print(f"[collect] empty dirs ({len(empty_dirs)}): {', '.join(empty_dirs)}", file=sys.stderr)
    if bad_headers:
        print(f"[collect] bad/unexpected headers in: {', '.join(bad_headers)}", file=sys.stderr)

if __name__ == "__main__":
    main()
