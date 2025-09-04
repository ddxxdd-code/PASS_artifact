#!/usr/bin/env python3
"""
Parse fio logs named <system>_<config>_<power>.log and extract total WRITE throughput.

- system: pass | thunderbolt
- config: c8d10 | c8d5 | c1d10
- power : 250 | 260 | 300 | 360 | 440 | 600

The script looks for a final/summary WRITE throughput in the log, supporting both:
  1) "WRITE=xxGiB/s" (preferred if present)
  2) "WRITE: bw=xxMiB/s" (standard fio summary format)
If multiple matches exist, the *last* occurrence is used. Throughput is output in GiB/s.

Output CSV columns: system,config,power,throughput(GiB/s)
"""

import argparse
import csv
import re
import sys
from pathlib import Path

SYSTEMS = ["pass", "thunderbolt"]
CONFIGS = ["c8d10", "c8d5", "c1d10"]
POWERS  = ["250", "260", "300", "360", "440", "600"]

# Patterns to capture total WRITE throughput in various fio styles
# Style A (custom/total line):  WRITE=12.34GiB/s
RE_WRITE_EQ = re.compile(r"\bWRITE\s*=\s*([0-9]*\.?[0-9]+)\s*([KMGT]?i?)B/s", re.IGNORECASE)

# Style B (fio summary):        WRITE: bw=1234MiB/s
RE_WRITE_BW = re.compile(r"\bWRITE:\s*.*?\bbw=\s*([0-9]*\.?[0-9]+)\s*([KMGT]?i?)B/s", re.IGNORECASE)

UNIT_TO_GIB = {
    "B/s":   1.0 / (1024**3),
    "KiB/s": 1.0 / (1024**2),
    "MiB/s": 1.0 / 1024.0,
    "GiB/s": 1.0,
    "TiB/s": 1024.0,
}

def to_gibs(value: float, unit_token: str) -> float:
    """Convert value with unit token like 'MiB/s', 'GiB/s', 'KiB/s', 'B/s' to GiB/s."""
    # Normalize token (e.g., "mib/s" -> "MiB/s")
    unit_token = unit_token.strip()
    # Standardize capitalization of the binary prefix
    token = unit_token.upper().replace("IB/S", "iB/s")  # handles MIB/S -> MiB/s
    # Fix the full token if only prefix given (e.g., "Mi" -> "MiB/s")
    if token.endswith("I") or token in {"K", "M", "G", "T", "KI", "MI", "GI", "TI"}:
        token = token + "B/S"
        token = token.replace("B/S", "iB/s")  # ensure iB/s
    # Handle bare K/M/G/T without i
    token = token.replace("KB/S", "KiB/s").replace("MB/S", "MiB/s").replace("GB/S", "GiB/s").replace("TB/S", "TiB/s")
    token = token.replace("KIB/S", "KiB/s").replace("MIB/S", "MiB/s").replace("GIB/S", "GiB/s").replace("TIB/S", "TiB/s")
    token = token.replace("B/S", "B/s")

    factor = UNIT_TO_GIB.get(token, None)
    if factor is None:
        # Fallback: assume MiB/s if unit is ambiguous
        factor = UNIT_TO_GIB["MiB/s"]
    return float(value) * factor

def extract_write_gibs(text: str) -> float | None:
    """Extract total WRITE throughput (GiB/s) from fio text. Prefer WRITE=..., else WRITE: bw=... ."""
    # Find all matches, use the last occurrence (typically the final summary)
    matches_eq = list(RE_WRITE_EQ.finditer(text))
    if matches_eq:
        val = float(matches_eq[-1].group(1))
        unit = matches_eq[-1].group(2) + "B/s"  # e.g., "Gi" -> "GiB/s"
        return to_gibs(val, unit)

    matches_bw = list(RE_WRITE_BW.finditer(text))
    if matches_bw:
        val = float(matches_bw[-1].group(1))
        unit = matches_bw[-1].group(2) + "B/s"
        return to_gibs(val, unit)

    return None

def main():
    ap = argparse.ArgumentParser(description="Extract total WRITE throughput (GiB/s) from fio logs into a CSV.")
    ap.add_argument("-d", "--dir", default=".", help="Directory containing <system>_<config>_<power>.log files")
    ap.add_argument("-o", "--out", default="throughput_gibs.csv", help="Output CSV filename")
    ap.add_argument("--digits", type=int, default=3, help="Decimal places for GiB/s (default: 3)")
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

                gibs = extract_write_gibs(text)
                if gibs is None:
                    print(f"[warn] no WRITE throughput found in {fpath}", file=sys.stderr)
                    continue

                rows.append([
                    system,
                    config,
                    int(power),
                    round(gibs, args.digits)
                ])

    # Write CSV
    outpath = Path(args.out)
    with outpath.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["system", "config", "power", "throughput(GiB/s)"])
        writer.writerows(rows)

    print(f"Wrote {outpath} with {len(rows)} rows.")

if __name__ == "__main__":
    main()
