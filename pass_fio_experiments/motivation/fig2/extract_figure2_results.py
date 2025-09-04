#!/usr/bin/env python3
import argparse
import csv
import re
from pathlib import Path
from collections import defaultdict

FILENAME_RE = re.compile(r'^(pass|thunderbolt)_(270|300|330|380|440)\.log$')
JOB_HEADER_RE = re.compile(r'^(\S+):\s*\(')

# Example lines we will parse:
#   "  write: IOPS=..., BW=3100MiB/s (3250MB/s)"
#   "   read: IOPS=..., BW=2.3GiB/s (2469MB/s)"
#   "  WRITE: bw=8242MiB/s (8643MB/s), ..."
BW_RE = re.compile(r'\bbw=\s*([0-9]*\.?[0-9]+)\s*([MG]i?B)/s', re.IGNORECASE)

# Old-style inline p99
P99_INLINE_RE = re.compile(r'\bp99=\s*([0-9]*\.?[0-9]+)')
PCTL_HEADER_RE = PCTL_HEADER_RE = re.compile(
    r'^(?:\s*)(c?lat)\s+percentiles\s+\((nsec|usec|msec)\):',
    re.IGNORECASE
)
# accept 99th, 99.0th, 99.00th, 99.000th, and allow an optional leading '|' on the line
PCTL_99TH_RE = re.compile(r'^\s*\|?\s*99(?:\.0+)?th=\[\s*([0-9]+)\s*\]')

UNIT_TO_USEC = {'nsec': 1/1000.0, 'usec': 1.0, 'msec': 1000.0}
UNIT_TO_GIB = {'MiB': 1/1024.0, 'GiB': 1.0}

def parse_bw_to_gibs(value: str, unit: str) -> float:
    val = float(value)
    u = unit
    if u.lower().startswith("mib"):
        return val * UNIT_TO_GIB['MiB']
    elif u.lower().startswith("gib"):
        return val * UNIT_TO_GIB['GiB']
    else:
        return val  # fallback

def collect_from_file(path: Path):
    """
    Return:
      last_group0_bw_gibs: float or 0.0 if not found
      p99_bursty: list of p99 latency values (usec) for jobs named 'bursty'
    """
    p99_bursty = []

    current_job = None
    pctl_unit = None
    in_pctl_block = False

    # Track "Run status group 0 (all jobs)" parsing
    in_group0 = False
    last_group0_bw_gibs = 0.0

    with path.open('r', errors='ignore') as f:
        for raw in f:
            line = raw.rstrip('\n')

            # Job header
            m_job = JOB_HEADER_RE.match(line)
            if m_job:
                current_job = m_job.group(1)
                pctl_unit = None
                in_pctl_block = False  # reset any ongoing percentile block
                continue

            # Percentiles header — only enter block if this job is bursty
            m_hdr = PCTL_HEADER_RE.match(line)
            if m_hdr:
                if current_job and 'bursty' in current_job:
                    pctl_unit = m_hdr.group(2).lower()
                    in_pctl_block = True
                else:
                    in_pctl_block = False
                continue

            # Inside a percentile block, pick out 99th — we only ever got here for bursty
            if in_pctl_block:
                m_99 = PCTL_99TH_RE.match(line)
                if m_99:
                    val = float(m_99.group(1))
                    usec = val * UNIT_TO_USEC.get(pctl_unit, 1.0)
                    p99_bursty.append(usec)
                    in_pctl_block = False  # done with this block

            # Inline p99=... (older fio style) — only if this job is bursty
            if current_job and 'bursty' in current_job.lower() and ('p99=' in line):
                paren = re.search(r'\((nsec|usec|msec)\)', line)
                unit = paren.group(1).lower() if paren else 'usec'
                m_p = P99_INLINE_RE.search(line)
                if m_p:
                    val = float(m_p.group(1))
                    usec = val * UNIT_TO_USEC[unit]
                    p99_bursty.append(usec)

            # Detect start of group 0 summary block
            if line.startswith('Run status group 0'):
                in_group0 = True
                continue

            # While in group 0, look for the total bw line(s). Keep the last one seen.
            if in_group0:
                m_bw = BW_RE.search(line)
                if m_bw:
                    bw_gibs = parse_bw_to_gibs(m_bw.group(1), m_bw.group(2))
                    last_group0_bw_gibs = bw_gibs
                # Heuristic to end the block: blank line or "Disk stats"
                if not line.strip() or line.startswith('Disk stats'):
                    in_group0 = False

    return last_group0_bw_gibs, p99_bursty

def main():
    ap = argparse.ArgumentParser(description="Extract last group-0 total BW (GiB/s) and average p99 of 'bursty'")
    ap.add_argument("-d", "--dir", type=Path, default=Path("."), help="Dir with <system>_<power>.log")
    ap.add_argument("--throughput_csv", default="throughput_total.csv", help="CSV of {system,power,throughput_GiBs}")
    ap.add_argument("--latency_csv", default="latency_bursty.csv", help="CSV of {system,power,p99_latency_usecs}")
    args = ap.parse_args()

    rows_thru, rows_lat = [], []
    thru = defaultdict(float)
    lat = defaultdict(list)

    for p in sorted(args.dir.iterdir()):
        if not p.is_file():
            continue
        m = FILENAME_RE.match(p.name)
        if not m:
            continue
        system, power = m.group(1), int(m.group(2))

        last_group0_bw_gibs, p99_bursty = collect_from_file(p)

        # Throughput: use ONLY the last total bandwidth from group 0 (if present)
        if last_group0_bw_gibs > 0.0:
            thru[(system, power)] = last_group0_bw_gibs

        # Latency: average p99 for 'bursty'
        for usec in p99_bursty:
            lat[(system, power)].append(usec)

    for (system, power), bw in thru.items():
        rows_thru.append({"system": system, "power": power, "throughput_GiBs": round(bw, 3)})

    for (system, power), vals in lat.items():
        if vals:
            avg_usecs = round(sum(vals) / len(vals))
            rows_lat.append({"system": system, "power": power, "p99_latency_usecs": avg_usecs})

    rows_thru.sort(key=lambda r: (r["system"], r["power"]))
    rows_lat.sort(key=lambda r: (r["system"], r["power"]))

    with open(args.throughput_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["system", "power", "throughput_GiBs"])
        w.writeheader()
        w.writerows(rows_thru)

    with open(args.latency_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["system", "power", "p99_latency_usecs"])
        w.writeheader()
        w.writerows(rows_lat)

    print(f"Wrote {args.throughput_csv} with {len(rows_thru)} rows")
    print(f"Wrote {args.latency_csv} with {len(rows_lat)} rows")

if __name__ == "__main__":
    main()
