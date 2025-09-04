#!/usr/bin/env python3
"""
find_optimal_pareto.py:
Select the Pareto‐optimal configuration under a power budget,
maximizing power usage (closest to budget) and minimizing latency.
"""

import argparse
import pandas as pd

def pareto_frontier(df, metric):
    df = df.sort_values(["power", metric], ascending=[True, True])
    frontier, best_lat = [], float("inf")
    for _, row in df.iterrows():
        lat = row[metric]
        if lat < best_lat:
            frontier.append(row)
            best_lat = lat
    return pd.DataFrame(frontier)

def select_best(frontier, budget):
    cand = frontier[frontier.power <= budget]
    return cand.iloc[-1] if not cand.empty else None

def main():
    p = argparse.ArgumentParser(
        description="Optimal config under power budget via Pareto frontier"
    )
    p.add_argument("--data",   required=True, help="path to data.dat")
    p.add_argument("--metric", choices=["p50","p99"], default="p50",
                   help="latency metric")
    p.add_argument("--budget", type=float, required=True,
                   help="power budget (W)")
    args = p.parse_args()

    df = pd.read_csv(args.data, header=None,
                     names=["cores","bandwidth","rapl","power","p50","p99"])
    frontier = pareto_frontier(df, args.metric)
    best = select_best(frontier, args.budget)

    if best is None:
        print(f"No config ≤ {args.budget}W")
        return

    print("Optimal configuration:")
    print(f"  cores       : {int(best.cores)}")
    print(f"  bandwidth   : {best.bandwidth}")
    print(f"  RAPL limit  : {best.rapl}")
    print(f"  power       : {best.power:.2f} W")
    print(f"  {args.metric} latency: {best[args.metric]:.2f} ms")

if __name__ == "__main__":
    main()

