import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# Set font sizes globally
plt.rcParams.update({
    'font.size': 12,       # Base font size
    'axes.titlesize': 14,  # Title size
    'axes.labelsize': 14,  # Axis label size
    'xtick.labelsize': 16, # X-axis tick size
    'ytick.labelsize': 16, # Y-axis tick size
    'legend.fontsize': 12  # Legend font size
})

# Load the data
data = pd.read_csv('throughput_ref.csv')

# Define mappings and constants
system_map = {"c8d10": "8 cores 10 disks", "c8d5": "8 cores 5 disks", "c1d10": "1 core 10 disks"}
method_map = {"thunderbolt": "SPDK + Thunderbolt", "pass": "PASS (Ours)"}
# methods = ["pass", "thunderbolt", "dynamic_rapl"]
methods = ["pass", "thunderbolt"]
colors = {"pass": "#1f77b4", "thunderbolt": "#ff7f0e"}
markers = {"pass": "o", "thunderbolt": "s"}

# Get unique systems and power budgets
systems = sorted(data["config"].unique(), key=lambda x: list(system_map.keys()).index(x))
power_budgets = sorted(data["power"].unique())

# Create subplots
fig, axes = plt.subplots(len(systems), 1, figsize=(8, 8), sharey=False)

# Plot each system in its own subplot
for idx, system in enumerate(systems):
    ax = axes[idx]
    system_data = data[data["config"] == system]

    # Determine the y-axis limit based on the `pass` method
    pass_data = system_data[system_data["system"] == "pass"]
    max_pass_value = pass_data["throughput"].max() if not pass_data.empty else 0
    y_limit = 1.1 * max_pass_value

    # Plot lines for each method
    for method in methods:
        y_values = []
        x_values = []
        for power_budget in power_budgets:
            method_data = system_data[(system_data["system"] == method) & (system_data["power"] == power_budget)]
            if not method_data.empty:
                latency = method_data["throughput"].values[0]
                y_values.append(latency)
                x_values.append(power_budget)

        # Add line for the current method
        ax.plot(
            x_values, y_values,
            marker=markers[method], color=colors[method],
            label=method_map[method] if idx == 0 else None,
            markersize=10, linewidth=2
        )

    # Formatting for each subplot
    ax.set_title(system_map[system])
    # ax.set_xticks(power_budgets)
    # ax.set_xticklabels([str(pb) for pb in power_budgets])
    ax.set_xlim(240, 600)
    ax.set_ylim(0, y_limit)
    ax.grid(axis='y', linestyle='--', alpha=0.7)
    if idx == len(systems) - 1:
        ax.set_xlabel("power")
    ax.set_ylabel("Throughput (GiB/s)")

# Add a common legend at the top
fig.legend(
    [method_map[method] for method in methods],
    loc="upper center", ncol=len(methods), bbox_to_anchor=(0.5, 1.01)
)

# Adjust layout
plt.tight_layout(rect=[0, 0, 1, 0.97])
plt.savefig("swrite_128k_throughput_all_in_one_line.pdf")
plt.close()

print("Stacked line graph by system generated and saved as swrite_128k_throughput_line_graph.pdf.")
