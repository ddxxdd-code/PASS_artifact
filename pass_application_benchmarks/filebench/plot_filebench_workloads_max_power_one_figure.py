import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import ScalarFormatter

# Set font sizes globally
plt.rcParams.update({
    'font.size': 12,
    'axes.titlesize': 16,
    'axes.labelsize': 16,
    'xtick.labelsize': 16,
    'ytick.labelsize': 16,
    'legend.fontsize': 12
})

# Load the data
data = pd.read_csv('filebench_combined_ref.csv')

# Constants
# methods = ["linux_rapl", "spdk_thunderbolt", "spdk_rapl", "pass_profiled"]
methods = ["spdk_thunderbolt", "pass_profiled"]
method_map = {
    "linux_rapl": "Linux + RAPL",
    "spdk_thunderbolt": "SPDK + Thunderbolt",
    "spdk_rapl": "SPDK + RAPL",
    "pass_profiled": "PASS (Ours)"
}
workload_map = {
    "varmail": "Varmail",
    "fileserver": "File Server",
    "webserver": "Web Server"
}
powercaps = [265, 300, 350, 400, 500]
bar_width = 0.25
hatches     = ["//", r"\\", "--", "xx"]

# Colors
colors      = {
    "pass_profiled": "#1f77b4",  # Blue
    "spdk_thunderbolt":       "#ff7f0e",  # Orange
    "spdk_rapl":              "#2ca02c",  # Green
    "linux_rapl":            "#d62728",  # Red-orange
}

# Create figure with 2 columns
fig, axes = plt.subplots(len(workload_map), 2, figsize=(8, 2.8 * len(workload_map)), gridspec_kw={'width_ratios': [3, 1]})

bar_handles = {}

for idx, workload in enumerate(workload_map):
    # Left column: Throughput vs Power
    ax = axes[idx, 0]
    workload_data = data[data["workload"] == workload]

    x_positions = np.arange(len(powercaps))
    for i, method in enumerate(methods):
        y_values = []
        x_offsets = []
        for j, powercap in enumerate(powercaps):
            method_data = workload_data[(workload_data["method"] == method) & (workload_data["powercap"] == powercap)]
            throughput = method_data["total throughput (ops/s)"].values[0] if not method_data.empty else 0
            y_values.append(throughput if throughput > 0 else 0)
            x_offsets.append(x_positions[j] + i * bar_width)
            if powercap == 260 and throughput:
                ax.text(x_positions[j] + i * bar_width, throughput, f"{int(throughput):,}", ha="center", va="bottom", fontsize=13)
        
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

    # Right column: throughput @500W
    ax_unlimited = axes[idx, 1]
    unlimited_methods = {
        "linux_rapl": "Linux",
        "spdk_rapl": "SPDK",
        "pass_profiled": "PASS (Ours)"
    }
    unlimited_labels = list(unlimited_methods.values())
    unlimited_values = []

    for m in unlimited_methods:
        unlimited_data = data[(data["method"] == m) & (data["powercap"] == 500) & (data["workload"] == workload)]
        if not unlimited_data.empty:
            val = unlimited_data["total throughput (ops/s)"].values[0]
            unlimited_values.append(val)
        else:
            unlimited_values.append(0)

    unlimited_bar = ax_unlimited.bar(unlimited_labels, unlimited_values, color=[colors.get(m, "#d62728") for m in unlimited_methods], edgecolor="black")

    if idx == len(workload_map) - 1: 
        ax_unlimited.set_xlabel("Power Budget: TDP")
        ax_unlimited.set_xticklabels(unlimited_labels, rotation=15)
    else:
        ax_unlimited.set_xticks([])
    ax_unlimited.ticklabel_format(style='scientific', axis='y', scilimits=(0, 0))
    ax_unlimited.grid(axis='y', linestyle='--', alpha=0.7)

# Global legend
fig.legend(bar_handles.values(), bar_handles.keys(), loc="upper center", ncol=len(bar_handles), bbox_to_anchor=(0.5, 0.995))

# Final layout
plt.tight_layout(rect=[0, 0, 1, 0.97])
plt.savefig("filebench_throughput_with_unlimited_insets.pdf")
plt.close()
print("Plot with insets saved as filebench_throughput_with_unlimited_insets.pdf.")
