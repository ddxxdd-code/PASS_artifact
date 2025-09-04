#!/usr/bin/env python3
import argparse
import csv
import os
import re
from statistics import mean
from typing import Tuple, Optional, List

# ---------- Parsing helpers ----------

def parse_raplpower(filepath: str, period_ms: int) -> Tuple[Optional[float], Optional[float]]:
    """
    Parse perf -I <period_ms> output with lines like:
         1.000826974   5.86 Joules power/energy-ram/
         1.000826974 130.26 Joules power/energy-pkg/

    Converts Joules -> Watts using: Watts = Joules / period_s
    Uses average of 50 entries after skipping the first 20.
    """
    if not os.path.isfile(filepath):
        raise FileNotFoundError(filepath)

    ram_joules: List[float] = []
    pkg_joules: List[float] = []

    joule_line_re = re.compile(
        r"""^\s*([0-9]+\.[0-9]+|\d+)\s+([0-9]+(?:\.[0-9]+)?)\s+Joules\s+power/energy-(ram|pkg)/""",
        re.VERBOSE
    )

    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if line.lstrip().startswith("#"):
                continue
            m = joule_line_re.match(line)
            if not m:
                continue
            _, counts_str, which = m.groups()
            joules = float(counts_str)
            if which == "ram":
                ram_joules.append(joules)
            elif which == "pkg":
                pkg_joules.append(joules)

    if not ram_joules and not pkg_joules:
        raise ValueError(f"No RAPL energy samples in {filepath}")

    period_s = period_ms / 1000.0

    def avg_sampled(values: List[float]) -> Optional[float]:
        if not values:
            return None
        sampled = values[20:70]  # skip first 20, average next 50
        if not sampled:
            return None
        return mean(sampled) / period_s

    cpu_W = avg_sampled(pkg_joules)
    ram_W = avg_sampled(ram_joules)
    return cpu_W, ram_W


def parse_fio_throughput_gib(filepath: str) -> Optional[float]:
    """
    Parse fio log for throughput in GiB/s.
    Handles BW=22.3GiB/s, BW=22800MiB/s, aggrb=..., etc.
    """
    if not os.path.isfile(filepath):
        return None

    bw_eq_re = re.compile(r'BW=\s*([0-9]+(?:\.[0-9]+)?)\s*(GiB|MiB|KiB|GB|MB|KB)/s')
    aggrb_re = re.compile(r'aggrb=\s*([0-9]+(?:\.[0-9]+)?)\s*([GMK]B)/s', re.IGNORECASE)

    def to_gibps(val: float, unit: str) -> float:
        unit = unit.strip()
        if unit == "GiB":
            return val
        if unit == "MiB":
            return val / 1024.0
        if unit == "KiB":
            return val / (1024.0 * 1024.0)
        if unit.upper() == "GB":
            return val * (1e9 / (1024.0**3))
        if unit.upper() == "MB":
            return val * (1e6 / (1024.0**3))
        if unit.upper() == "KB":
            return val * (1e3 / (1024.0**3))
        return val

    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()

    m = bw_eq_re.search(text)
    if m:
        return to_gibps(float(m.group(1)), m.group(2))

    m = aggrb_re.search(text)
    if m:
        return to_gibps(float(m.group(1)), m.group(2))

    return None


# ---------- Main ----------

def main():
    ap = argparse.ArgumentParser(description="Extract power breakdown from pass_<power> logs.")
    ap.add_argument("--powers", nargs="*", type=int,
                    default=[265, 300, 360, 440, 530],
                    help="System power caps to process")
    ap.add_argument("--rapl-period-ms", type=int, default=1000,
                    help="RAPL sampling period used by perf -I (ms)")
    ap.add_argument("--fio-base", type=str, default="pass_{power}.log",
                    help="Pattern for fio logs (default: pass_{power}.log)")
    ap.add_argument("--rapl-base", type=str, default="pass_{power}.raplpower",
                    help="Pattern for rapl logs (default: pass_{power}.raplpower)")
    ap.add_argument("--out", type=str, default="power_breakdown.csv",
                    help="Output CSV filename")
    ap.add_argument("--baseline-throughput-gibps", type=float, default=22.3,
                    help="Baseline throughput (GiB/s) for 150W disk power")
    ap.add_argument("--disk-power-at-baseline", type=float, default=150.0,
                    help="Disk power (W) at baseline throughput")
    args = ap.parse_args()

    rows = []
    for p in args.powers:
        rapl_path = args.rapl_base.format(power=p)
        fio_path = args.fio_base.format(power=p)

        cpu_W, ram_W = parse_raplpower(rapl_path, args.rapl_period_ms)
        if cpu_W is None or ram_W is None:
            raise SystemExit(f"Missing CPU or RAM samples in {rapl_path}")

        thr_gibps = parse_fio_throughput_gib(fio_path)
        if thr_gibps is None:
            raise SystemExit(f"No throughput found in fio log {fio_path}")

        # Disk power scaling
        disk_power = round((thr_gibps / args.baseline_throughput_gibps) * args.disk_power_at_baseline)

        # Other power
        other_power = p - cpu_W - disk_power
        if other_power < 0 and abs(other_power) < 5:
            other_power = 0.0

        rows.append({
            "system_power": p,
            "cpu_power": round(cpu_W),
            "disk_power": int(disk_power),
            "other_power": round(other_power),
            "ram_power": round(ram_W, 1),
        })

    # Sort by system_power descending
    rows.sort(key=lambda r: r["system_power"], reverse=True)

    # Write CSV
    with open(args.out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["system_power", "cpu_power", "disk_power", "other_power", "ram_power"])
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {args.out}")
    for r in rows:
        print("{system_power},{cpu_power},{disk_power},{other_power},{ram_power}".format(**r))


if __name__ == "__main__":
    main()
