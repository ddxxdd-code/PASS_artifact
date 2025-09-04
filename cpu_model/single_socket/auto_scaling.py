#!/usr/bin/env python3
"""
auto_resctl.py: Compute, select, and apply the Pareto‐optimal CPU config
under a power budget by invoking resctl.sh.
"""

import argparse
import pandas as pd
import subprocess
import sys

def pareto_frontier(df, metric):
    df = df.sort_values(["power", metric], ascending=[True, True])
    frontier = []
    best_lat = float("inf")
    for _, row in df.iterrows():
        lat = row[metric]
        if lat < best_lat:
            frontier.append(row)
            best_lat = lat
    return pd.DataFrame(frontier)

def select_best(frontier, budget):
    valid = frontier[frontier.power <= budget]
    return valid.iloc[-1] if not valid.empty else None

def main():
    p = argparse.ArgumentParser(
        description="Auto‐apply optimal CPU config under power budget"
    )
    p.add_argument("--data",   required=True,
                   help="path to data.dat (CSV, no header)")
    p.add_argument("--budget", type=float, required=True,
                   help="power budget (W)")
    p.add_argument("--metric", choices=["p50","p99"], default="p50",
                   help="latency metric to minimize")
    p.add_argument("--resctl", default="./resctl.sh",
                   help="path to resctl.sh script")
    args = p.parse_args()

    df = pd.read_csv(args.data, header=None,
                     names=["cores","bandwidth","rapl","power","p50","p99"])
    frontier = pareto_frontier(df, args.metric)
    best = select_best(frontier, args.budget)

    if best is None:
        print(f"No config ≤ {args.budget}W", file=sys.stderr)
        sys.exit(1)

    cores    = int(best.cores)
    bw_pct   = int(best.bandwidth)
    rapl_lim = int(best.rapl)

    # invoke the control script
    cmd = [args.resctl, str(cores), str(bw_pct), str(rapl_lim)]
    ret = subprocess.run(cmd)
    if ret.returncode != 0:
        print(f"Error: {args.resctl} exited with {ret.returncode}", file=sys.stderr)
        sys.exit(ret.returncode)

    print("Applied optimal config:")
    print(f"  cores       : {cores}")
    print(f"  bandwidth   : {bw_pct}%")
    print(f"  RAPL limit  : {rapl_lim} W")

if __name__ == "__main__":
    main()

