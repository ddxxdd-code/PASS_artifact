#!/usr/bin/python3
"""
extract_figure12_results.py

Parse fio logs named <system>_<power>.log where:
  - system in {pass, thunderbolt}
  - power  in {265, 300, 360, 440}

Extract ALL occurrences of P99 (99.00th) latency from the logs, handling units
(nsec/usec/msec), average them per file, convert to microseconds (µs), and
write a CSV with columns:
    system,power,p99 latency

Usage:
  python3 extract_figure12_results.py            # looks for default systems/powers
  python3 extract_figure12_results.py --out fig12.csv
  python3 extract_figure12_results.py --systems pass thunderbolt --powers 265 300 360 440
  python3 extract_figure12_results.py --glob-extra "*_extra.log"   # optional extra files

Notes:
- Looks for "clat percentiles (usec|nsec|msec):" or "lat percentiles (...)" blocks,
  then scans for lines containing "99.00th=[   123]" etc.
- If multiple p99 values are present in one log (e.g., multiple jobs/sections),
  they are all averaged.
"""

import argparse
import csv
import glob
import os
import re
from statistics import mean
from typing import List, Optional, Tuple

# Regex to detect the start of a percentile block and capture its unit
PCTL_HEADER_RE = re.compile(
    r'^\s*(?:c?lat|lat)\s+percentiles\s+\((nsec|usec|msec)\)\s*:\s*$', re.IGNORECASE
)

# Regex to find the 99.00th percentile value within a percentile block
# Matches e.g.: "  | 99.00th=[    123]", " 99.00th=[  1,234]" (commas tolerated)
P99_LINE_RE = re.compile(
    r'99\.00th=\[\s*([0-9][0-9,]*)\s*\]'
)

def unit_to_usec(value: float, unit: str) -> float:
    u = unit.lower()
    if u == "usec":
        return value
    if u == "nsec":
        return value / 1000.0
    if u == "msec":
        return value * 1000.0
    # Unknown unit; assume µs
    return value

def parse_p99_usecs_from_fio_log(path: str) -> List[float]:
    """
    Parse a fio .log file, extract all p99 latency values (converted to µs).
    We track the current percentile block's unit via the header line and apply
    it to subsequent "99.00th=[...]" lines until another header is encountered.
    """
    p99s_usec: List[float] = []
    if not os.path.isfile(path):
        return p99s_usec

    current_unit: Optional[str] = None

    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            # Update unit when we enter a new percentile block
            m_header = PCTL_HEADER_RE.search(line)
            if m_header:
                current_unit = m_header.group(1)
                continue

            # Extract 99.00th within the current block (requires known unit)
            m_p99 = P99_LINE_RE.search(line)
            if m_p99 and current_unit:
                raw = m_p99.group(1).replace(",", "")  # tolerate 1,234 formatting
                try:
                    v = float(raw)
                except ValueError:
                    continue
                p99s_usec.append(unit_to_usec(v, current_unit))

    return p99s_usec

def average_or_none(values: List[float]) -> Optional[float]:
    return mean(values) if values else None

def main():
    ap = argparse.ArgumentParser(description="Extract average p99 latency (µs) from fio logs into CSV.")
    ap.add_argument("--systems", nargs="+", default=["pass", "thunderbolt"],
                    help="Systems to scan (default: pass thunderbolt)")
    ap.add_argument("--powers", nargs="+", type=int, default=[265, 300, 360, 440],
                    help="Powers to scan (default: 265 300 360 440)")
    ap.add_argument("--out", default="figure12_results.csv",
                    help="Output CSV filename (default: figure12_results.csv)")
    ap.add_argument("--glob-extra", default=None,
                    help="Optional glob to include additional files (e.g. '*_extra.log')")
    args = ap.parse_args()

    rows: List[Tuple[str, int, int]] = []  # (system, power, avg_p99_usec_rounded)

    # Deterministic order
    for system in args.systems:
        for power in args.powers:
            fname = f"{system}_{power}.log"
            p99s = parse_p99_usecs_from_fio_log(fname)
            avg_usec = average_or_none(p99s)

            if avg_usec is None:
                # Gracefully skip missing/no-p99 logs, but let user know
                print(f"[WARN] No p99 found in {fname}; skipping.")
                continue

            rows.append((system, power, int(round(avg_usec))))

    # Optionally include extra files matched by a glob pattern (doesn't change default targets)
    if args.glob_extra:
        for path in sorted(glob.glob(args.glob_extra)):
            # Try to infer system & power from "<system>_<power>.log"
            base = os.path.basename(path)
            m = re.match(r'^(pass|thunderbolt)_(\d+)\.log$', base)
            if not m:
                continue
            system = m.group(1)
            power = int(m.group(2))
            p99s = parse_p99_usecs_from_fio_log(path)
            avg_usec = average_or_none(p99s)
            if avg_usec is None:
                print(f"[WARN] No p99 found in {path}; skipping.")
                continue
            rows.append((system, power, int(round(avg_usec))))

    # Sort by system then power ascending
    rows.sort(key=lambda r: (r[0], r[1]))

    # Write CSV with the exact header requested (with a space in column name)
    with open(args.out, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["system", "power", "p99 latency"])
        for system, power, p99u in rows:
            writer.writerow([system, power, p99u])

    print(f"Wrote {args.out}")
    for r in rows:
        print(f"{r[0]},{r[1]},{r[2]}")

if __name__ == "__main__":
    main()
