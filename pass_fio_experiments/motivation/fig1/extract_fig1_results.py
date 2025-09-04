#!/usr/bin/env python3
import re
import argparse
from pathlib import Path
from statistics import mean
import csv
from typing import List

# Default systems + ranges
DEFAULT_SYSTEMS = ["linux", "spdk_dynamic", "spdk_static"]

# Regexes to parse fio text
RE_BURSTY_HEADER = re.compile(r"^bursty:\s*\(g=\d+\):")
RE_ANY_JOB_HDR   = re.compile(r"^[A-Za-z0-9_\-]+:\s*\(g=\d+\):")
# Now supports nsec/usec/msec
RE_CLAT_UNIT     = re.compile(r"^\s*clat percentiles \((nsec|usec|msec)\):")
RE_P99           = re.compile(r"\b99\.00th=\[\s*(\d+)\s*\]")

def _to_usec(val: int, unit: str) -> int:
    """
    Convert fio percentile value to microseconds.
    - nsec -> ceil(ns/1000) so very small nonzero values don’t become 0
    - usec -> unchanged
    - msec -> *1000
    """
    if unit == "nsec":
        return (val + 999) // 1000
    if unit == "msec":
        return val * 1000
    # "usec"
    return val

def parse_bursty_p99s(text: str) -> List[int]:
    """
    Extract all 99th percentile clat values for 'bursty' jobs in a fio log.
    Returns values in microseconds; converts from nsec/msec if needed.
    """
    p99s = []
    in_bursty = False
    current_unit = "usec"

    for line in text.splitlines():
        if RE_BURSTY_HEADER.search(line):
            in_bursty = True
            current_unit = "usec"
            continue

        # If we were inside a bursty block and a new job header starts, close the bursty block
        if in_bursty and RE_ANY_JOB_HDR.match(line) and not RE_BURSTY_HEADER.search(line):
            in_bursty = False
            current_unit = "usec"
            continue

        if in_bursty:
            m_unit = RE_CLAT_UNIT.match(line)
            if m_unit:
                current_unit = m_unit.group(1)  # 'nsec' | 'usec' | 'msec'
                continue

            m_p99 = RE_P99.search(line)
            if m_p99:
                raw = int(m_p99.group(1))
                p99s.append(_to_usec(raw, current_unit))

    return p99s

def main():
    ap = argparse.ArgumentParser(
        description="Extract bursty p99 latency (usec) from fio logs and write CSV."
    )
    ap.add_argument("--dir", type=str, default=".", help="Directory containing logs (default: .)")
    ap.add_argument("--t", type=int, default=30, help="Runtime suffix used in filenames, e.g., t30 (default: 30)")
    ap.add_argument("--systems", type=str, nargs="*", default=DEFAULT_SYSTEMS,
                    help=f"Systems to scan (default: {','.join(DEFAULT_SYSTEMS)})")
    ap.add_argument("--out", type=str, default="latency_data.csv",
                    help="Output CSV filename (default: latency_data.csv)")
    args = ap.parse_args()

    logdir = Path(args.dir)
    outfile = Path(args.out)

    # Collect rows as (system, background_jobs, p99_latency_int)
    rows = []
    for system in args.systems:
        for n in range(0, 9):
            fname = logdir / f"{system}_n{n}_t{args.t}.log"
            if not fname.exists():
                continue
            text = fname.read_text(errors="ignore")
            p99s = parse_bursty_p99s(text)
            if not p99s:
                continue
            avg_p99 = round(mean(p99s))
            rows.append((system, n, int(avg_p99)))

    # Write CSV with header
    outfile.parent.mkdir(parents=True, exist_ok=True)
    with outfile.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["system", "background_jobs", "p99_latency"])  # p99_latency in usec
        for system, n, p99 in rows:
            writer.writerow([system, n, p99])

    print(f"Wrote {len(rows)} rows to {outfile}")

if __name__ == "__main__":
    main()
