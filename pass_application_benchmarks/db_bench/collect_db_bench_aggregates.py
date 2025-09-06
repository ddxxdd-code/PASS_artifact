#!/usr/bin/env python3
"""
Collect all <system>_db_bench_aggregated_metrics.csv files from directories
named <system>_<powercap> and merge them into a single CSV.

Each input CSV has exactly one data row with this header:
  method,powercap,workload,throughput (ops/s),p99 latency (µs)

Usage examples:
  # Defaults: PASS=500, TB=500, LINUX=500
  python3 collect_db_bench_aggregates.py

  # Explicit caps
  python3 collect_db_bench_aggregates.py \
      --pass-caps 500 265 300 350 400 \
      --tb-caps 500 265 300 350 400 \
      --linux-caps 500 \
      --out db_bench_aggregated_all.csv
"""
import argparse
import csv
import sys
from pathlib import Path
from typing import Dict, List

OUTPUT_COLS = [
    "method",
    "powercap",
    "workload",
    "throughput (ops/s)",
    "p99 latency (µs)",
]

FILENAME_TEMPLATE = "{system}_db_bench_aggregated_metrics.csv"

def parse_args():
    ap = argparse.ArgumentParser(description="Merge db_bench per-dir aggregated CSVs into one file.")
    ap.add_argument("--out", default="db_bench_aggregated_all.csv",
                    help="Output CSV path (default: db_bench_aggregated_all.csv)")
    ap.add_argument("--pass-caps", nargs="+", type=int, default=[500],
                    help="List of PASS power caps (e.g., 500 265 300 350 400)")
    ap.add_argument("--tb-caps", nargs="+", type=int, default=[500],
                    help="List of Thunderbolt power caps (e.g., 500 265 300 350 400)")
    ap.add_argument("--linux-caps", nargs="+", type=int, default=[500],
                    help="List of Linux power caps (e.g., 500)")
    ap.add_argument("--root", default=".", help="Root directory to scan (default: current dir)")
    return ap.parse_args()

def norm_key(s: str) -> str:
    """Normalize header keys to be robust to micro symbol variants/whitespace/case."""
    return s.strip().replace("μ", "µ").lower()

def find_csv_path(system: str, cap: int, root: Path) -> Path:
    """Return the expected CSV path inside <system>_<cap>/"""
    d = root / f"{system}_{cap}"
    return d / FILENAME_TEMPLATE.format(system=system)

def validate_and_extract_row(csv_path: Path) -> List[str] | None:
    """
    Read a single-row CSV and return values in OUTPUT_COLS order.
    Returns None if header missing or row missing.
    """
    with csv_path.open("r", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            return None

        # Build a mapping from normalized->original header for this file
        original_fields = reader.fieldnames
        norm2orig: Dict[str, str] = {norm_key(k): k for k in original_fields}

        # Ensure all required columns exist (normalized)
        missing = [col for col in OUTPUT_COLS if norm_key(col) not in norm2orig]
        if missing:
            sys.stderr.write(f"[collect] {csv_path} missing columns: {missing}\n")
            return None

        try:
            row = next(reader)  # exactly one data row
        except StopIteration:
            sys.stderr.write(f"[collect] {csv_path} had header but no data row.\n")
            return None

        # Emit in strict OUTPUT_COLS order, pulling from original keys
        ordered = [row[norm2orig[norm_key(col)]].strip() for col in OUTPUT_COLS]
        return ordered

def main():
    args = parse_args()
    root = Path(args.root).resolve()
    out_path = Path(args.out)

    plan = [
        ("pass", args.pass_caps),
        ("thunderbolt", args.tb_caps),
        ("linux", args.linux_caps),
    ]

    rows: List[List[str]] = []
    missing_dirs, missing_files = [], []

    for system, caps in plan:
        for cap in caps:
            d = root / f"{system}_{cap}"
            if not d.is_dir():
                missing_dirs.append(str(d))
                continue
            csv_path = find_csv_path(system, cap, root)
            if not csv_path.is_file():
                missing_files.append(str(csv_path))
                continue

            ordered = validate_and_extract_row(csv_path)
            if ordered is not None:
                rows.append(ordered)

    # Write output
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(OUTPUT_COLS)
        writer.writerows(rows)

    # Diagnostics
    sys.stderr.write(f"[collect] wrote {len(rows)} rows → {out_path}\n")
    if missing_dirs:
        sys.stderr.write(f"[collect] missing dirs ({len(missing_dirs)}): {', '.join(missing_dirs)}\n")
    if missing_files:
        sys.stderr.write(f"[collect] missing files ({len(missing_files)}): {', '.join(missing_files)}\n")

if __name__ == "__main__":
    main()
