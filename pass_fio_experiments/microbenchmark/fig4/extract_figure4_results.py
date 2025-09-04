#!/usr/bin/env python3
"""
Read fio logs named <system>_<config>_<power>.log and extract mean p99 latency.

- system ∈ {pass, thunderbolt}
- config ∈ {c8d10, c8d5, c1d10}
- power  ∈ {260, 300, 360, 440}

For each file, we:
  * find all "clat percentiles (usec|nsec|msec)" blocks,
  * extract the 99.00th value from each block,
  * convert to usec if needed,
  * average across all matches in the file (rounded to nearest int).

Output CSV columns: system,config,power,p99 latency
"""

import argparse
import re
import sys
from pathlib import Path
import csv
from statistics import mean

SYSTEMS = ["pass", "thunderbolt"]
CONFIGS = ["c8d10", "c8d5", "c1d10"]
POWERS  = ["260", "300", "360", "440"]

# Regex to find each "clat percentiles (unit):" header and capture the unit
PCTL_HEADER_RE = re.compile(r"clat percentiles \((usec|nsec|msec)\):", re.IGNORECASE)

# Regex to find the 99.00th entry within a block line, tolerant of spaces
P99_RE = re.compile(r"99\.00th=\[\s*(\d+)\s*\]")

def extract_p99_usec(text: str) -> list[int]:
    """
    Return a list of p99 latency values in usec found in the fio output text.
    We scan each 'clat percentiles (unit):' block and look for 99.00th inside
    the next few lines (fio formats percentiles across 1-2 wrapped lines).
    """
    p99_values_usec = []
    for m in PCTL_HEADER_RE.finditer(text):
        unit = m.group(1).lower()
        start = m.end()

        # Grab a small window after the header (the percentile table typically
        # spans 1-3 lines prefixed with a bar and spaces). Take the next ~6 lines.
        # This avoids accidentally mixing with later sections.
        block = []
        lines = text[start:].splitlines()
        for line in lines[:8]:  # small, focused window
            block.append(line)
        block_text = "\n".join(block)

        for p in P99_RE.finditer(block_text):
            val = int(p.group(1))
            # Convert to usec based on unit
            if unit == "usec":
                usec = val
            elif unit == "nsec":
                # round to nearest usec
                usec = round(val / 1000.0)
            elif unit == "msec":
                usec = round(val * 1000.0)
            else:
                continue
            p99_values_usec.append(int(usec))
    return p99_values_usec

def main():
    ap = argparse.ArgumentParser(description="Extract mean p99 latency (usec) from fio logs and write CSV.")
    ap.add_argument("-o", "--out", default="p99_latency.csv", help="Output CSV filename (default: p99_latency.csv)")
    ap.add_argument("-d", "--dir", default=".", help="Directory containing the .log files (default: current dir)")
    args = ap.parse_args()

    base = Path(args.dir)
    rows = []

    for system in SYSTEMS:
        for config in CONFIGS:
            for power in POWERS:
                fname = f"{system}_{config}_{power}.log"
                fpath = base / fname
                if not fpath.exists():
                    print(f"[warn] missing file: {fpath}", file=sys.stderr)
                    continue

                try:
                    text = fpath.read_text(errors="ignore")
                except Exception as e:
                    print(f"[warn] failed to read {fpath}: {e}", file=sys.stderr)
                    continue

                p99s = extract_p99_usec(text)
                if not p99s:
                    print(f"[warn] no p99 found in {fpath}", file=sys.stderr)
                    continue

                avg_p99 = int(round(mean(p99s)))
                rows.append([system, config, power, avg_p99])

    # Write CSV
    outpath = Path(args.out)
    with outpath.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["system", "config", "power", "p99 latency"])
        writer.writerows(rows)

    print(f"Wrote {outpath} with {len(rows)} rows.")

if __name__ == "__main__":
    main()
