#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import ScalarFormatter

# ────────────────────────────────── Style ────────────────────────────────── #
plt.rcParams.update({
    "font.size":       12,
    "axes.titlesize":  16,
    "axes.labelsize":  16,
    "xtick.labelsize": 16,
    "ytick.labelsize": 16,
    "legend.fontsize": 12,
})

# ──────────────────────────────── Constants ─────────────────────────────── #
methods      = ["linux_rapl", "cpu_thunderbolt", "cpu_rapl", "pass_profiled_new_new"]
method_map   = {
    "cpu_thunderbolt":      "SPDK + Thunderbolt",
    "cpu_rapl":             "SPDK + RAPL",
    "pass_profiled_new_new":"PASS (Ours)",
    "linux_rapl":           "Linux + RAPL",
}
workload_map = {
    "workloada": "Workload A",
    "workloadb": "Workload B",
    "workloadc": "Workload C",
    "workloadd": "Workload D",
    "workloadf": "Workload F",
}
powercaps    = [265, 280, 330, 375, 470]
bar_width    = 0.20
hatches      = ["//", r"\\", "--", "xx"]
colors       = {
    "pass_profiled_new_new": "#1f77b4",
    "cpu_thunderbolt":       "#ff7f0e",
    "cpu_rapl":              "#2ca02c",
    "linux_rapl":            "#d62728",
}

# ────────────────────────────── Load data ──────────────────────────────── #
data      = pd.read_csv("ycsb_throughput_combined.csv")
workloads = ["workloada", "workloadb", "workloadc", "workloadd", "workloadf"]

# ───────────────────────────── Figure setup ─────────────────────────────── #
fig, axes = plt.subplots(len(workloads), 2,
                         figsize=(12, 3 * len(workloads)),
                         gridspec_kw={'width_ratios': [4, 1]})
bar_handles = {}

# ───────────────────────────── Main plotting ───────────────────────────── #
center_offset = bar_width * (len(methods) - 1) / 2
x_positions   = np.arange(len(powercaps))  # base positions for powercaps

for idx, workload in enumerate(workloads):
    workload_data = data[data["workload"] == workload]

    # ── Throughput subplot ──
    ax = axes[idx, 0]
    for i, method in enumerate(methods):
        y_vals, x_offs = [], []
        for j, pc in enumerate(powercaps):
            row = workload_data[
                (workload_data["method"] == method) &
                (workload_data["powercap"] == pc)
            ]
            thr = row["throughput (ops/s)"].iat[0] if not row.empty else 0
            y_vals.append(thr)
            x_offs.append(x_positions[j] + i * bar_width)

        bars = ax.bar(x_offs, y_vals,
                      bar_width,
                      color=colors[method],
                      edgecolor="black",
                      hatch=hatches[i])
        if method_map[method] not in bar_handles:
            bar_handles[method_map[method]] = bars[0]

    ax.yaxis.set_major_formatter(ScalarFormatter(useMathText=True))
    ax.ticklabel_format(style="scientific", axis="y", scilimits=(0, 0))
    ax.set_ylabel(f"{workload_map[workload]}\nThroughput (ops/s)")
    ax.grid(axis="y", linestyle="--", alpha=0.7)
    if idx == len(workloads) - 1:
        ax.set_xticks(x_positions + center_offset)
        ax.set_xticklabels([str(pc) for pc in powercaps])
        ax.set_xlabel("Power budget (W)")
    else:
        ax.set_xticks([])

    # ── Tail Latency subplot ──
    ax_lat = axes[idx, 1]
    latency_methods = {
        "linux_rapl": "Linux",
        "cpu_rapl": "SPDK",
        "pass_profiled_new_new": "PASS (Ours)"
    }
    latency_labels = list(latency_methods.values())
    latency_values = []

    for m in latency_methods:
        row = workload_data[
            (workload_data["method"] == m) &
            (workload_data["powercap"] == 470)
        ]
        if not row.empty:
            val = row["avg read P99 latency (µs)"].values[0]
            latency_values.append(val)
        else:
            latency_values.append(0)

    ax_lat.bar(latency_labels,
               latency_values,
               color=[colors.get(m, "#d62728") for m in latency_methods],
               edgecolor="black")
    ax_lat.set_ylabel("Read P99 Latency (µs)")
    ax_lat.set_xticklabels(latency_labels, rotation=15)
    ax_lat.grid(axis='y', linestyle='--', alpha=0.7)

# ───────────── Legend, layout, export ───────────── #
fig.legend(bar_handles.values(),
           bar_handles.keys(),
           loc="upper center",
           ncol=len(bar_handles),
           bbox_to_anchor=(0.53, 0.99))

plt.tight_layout(rect=[0, 0, 1, 0.975])
plt.savefig("ycsb_throughput_with_latency_insets.pdf")
plt.close()
print("Combined plot with latency insets saved as ycsb_throughput_with_latency_insets.pdf.")
