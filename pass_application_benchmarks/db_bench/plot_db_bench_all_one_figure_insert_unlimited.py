import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import ScalarFormatter

# Font sizes globally
plt.rcParams.update({
    'font.size': 12,
    'axes.titlesize': 16,
    'axes.labelsize': 16,
    'xtick.labelsize': 16,
    'ytick.labelsize': 16,
    'legend.fontsize': 12
})

# Load the data
data = pd.read_csv('db_bench_combined.csv')

# Define constants
# methods = ["linux_rapl", "spdk_thunderbolt", "spdk_rapl", "pass_profiled"]
methods = ["spdk_thunderbolt", "pass_profiled"]
method_map = {
    "spdk_thunderbolt": "SPDK + Thunderbolt",
    "spdk_rapl": "SPDK + RAPL",
    "pass_profiled": "PASS (Ours)",
    "linux_rapl": "Linux + RAPL"
}
workload_map = {
    "fillseq": "Sequential fill",
    "fillsync": "Synchronized fill",
    "overwrite": "Overwrite"
}
powercaps = [265, 280, 330, 375, 470]
bar_width = 0.25
hatches = ["//", r"\\", "--", "xx"]
colors = {
    "pass_profiled": "#1f77b4",
    "spdk_thunderbolt": "#ff7f0e",
    "spdk_rapl": "#2ca02c",
    "linux_rapl": "#d62728",
}

# Create subplot grid: 2 columns (throughput, unlimited)
fig, axes = plt.subplots(len(workload_map), 2, figsize=(8, 2.8 * len(workload_map)), gridspec_kw={'width_ratios': [3, 1]})
bar_handles = {}

for idx, workload in enumerate(workload_map):
    workload_data = data[data["workload"] == workload]

    # ── Throughput subplot ─────────────────────────
    ax = axes[idx, 0]
    x_positions = np.arange(len(powercaps))
    for i, method in enumerate(methods):
        y_values = []
        x_offsets = []
        for j, powercap in enumerate(powercaps):
            method_data = workload_data[(workload_data["method"] == method) & (workload_data["powercap"] == powercap)]
            throughput = method_data["throughput (ops/s)"].values[0] if not method_data.empty else 0
            y_values.append(throughput)
            x_offsets.append(x_positions[j] + i * bar_width)

        bars = ax.bar(x_offsets, y_values, bar_width, color=colors[method], edgecolor="black", hatch=hatches[i])
        if method_map[method] not in bar_handles:
            bar_handles[method_map[method]] = bars[0]

    ax.yaxis.set_major_formatter(ScalarFormatter(useMathText=True))
    ax.ticklabel_format(style='scientific', axis='y', scilimits=(0, 0))
    ax.set_ylabel(f"{workload_map[workload]}\nThroughput (ops/s)")
    ax.grid(axis='y', linestyle='--', alpha=0.7)
    group_center = bar_width / 2
    if idx == len(workload_map) - 1:
        ax.set_xticks(x_positions + group_center)
        ax.set_xticklabels([str(pc) for pc in powercaps])
        ax.set_xlabel("Power budget (W)")
    else:
        ax.set_xticks([])

    # ── Unlimited inset subplot ──────────────────────
    ax_unlimited = axes[idx, 1]
    unlimited_methods = {
        "linux_rapl": "Linux",
        "spdk_rapl": "SPDK",
        "pass_profiled": "PASS (Ours)"
    }
    unlimited_labels = list(unlimited_methods.values())
    unlimited_values = []

    for m in unlimited_methods:
        unlimited_data = workload_data[(workload_data["method"] == m) & (workload_data["powercap"] == 470)]
        if not unlimited_data.empty:
            val = unlimited_data["throughput (ops/s)"].values[0]
            unlimited_values.append(val)
        else:
            unlimited_values.append(0)

    ax_unlimited.bar(unlimited_labels, unlimited_values,
                   color=[colors.get(m, "#d62728") for m in unlimited_methods],
                   edgecolor="black")
    if idx == len(workload_map) - 1: 
        ax_unlimited.set_xlabel("Power Budget: TDP")
        ax_unlimited.set_xticklabels(unlimited_labels, rotation=15)
    else:
        ax_unlimited.set_xticks([])
    ax_unlimited.grid(axis='y', linestyle='--', alpha=0.7)

# Legend at top
fig.legend(bar_handles.values(), bar_handles.keys(), loc="upper center", ncol=len(bar_handles), bbox_to_anchor=(0.5, 0.995))

# Final layout
plt.tight_layout(rect=[0, 0, 1, 0.97])
plt.savefig("db_bench_throughput_with_unlimited_power_case.pdf")
plt.close()

print("Figure with throughput and non adaptive case saved as db_bench_throughput_with_unlimited_power_case.pdf.")
