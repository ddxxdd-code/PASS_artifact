#!/usr/bin/env python3
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
data = pd.read_csv("latency_ref.csv")

# Define mappings and constants
system_map = {"c8d10": "8 cores 10 disks", "c8d5": "8 cores 5 disks", "c1d10": "1 core 10 disks"}
method_map = {"thunderbolt": "SPDK + Thunderbolt", "pass": "PASS (Ours)"}
methods = ["pass", "thunderbolt"]
colors = {"pass": "#1f77b4", "thunderbolt": "#ff7f0e"}
markers = {"pass": "o", "thunderbolt": "s"}  # Different markers for clarity

# Get unique systems and power budgets
systems = sorted(data["config"].unique(), key=lambda x: list(system_map.keys()).index(x))
power_budgets = sorted(data["power"].unique())

# Create subplots (one per system)
fig, axes = plt.subplots(len(systems), 1, figsize=(8, 8), sharey=False)

for idx, system in enumerate(systems):
    ax = axes[idx]
    system_data = data[data["config"] == system]
    
    # Determine y-axis limit based on "pass" method
    pass_data = system_data[system_data["system"] == "pass"]
    max_pass_value = pass_data["p99 latency"].max() if not pass_data.empty else 0
    y_limit = 1.1 * max_pass_value
    
    # Plot lines for each method
    for method in methods:
        y_values = []
        for power_budget in power_budgets:
            method_data = system_data[(system_data["system"] == method) & (system_data["power"] == power_budget)]
            latency = method_data["p99 latency"].values[0] if not method_data.empty else np.nan
            y_values.append(latency)
        
        ax.plot(
            power_budgets, y_values,
            label=method_map[method] if idx == 0 else None,
            color=colors[method],
            marker=markers[method],
            linewidth=2
        )
    
    # Formatting
    ax.set_title(system_map[system])
    ax.set_xticks(power_budgets)
    ax.set_yscale("log")
    ax.grid(True, linestyle="--", alpha=0.7)
    if idx == len(systems) - 1:
        ax.set_xlabel("Power budget (W)")
    ax.set_ylabel("p99 Latency (µs)")

# Add legend at the top
fig.legend(
    [method_map[m] for m in methods],
    loc="upper center", ncol=len(methods), bbox_to_anchor=(0.5, 1)
)

plt.tight_layout(rect=[0, 0, 1, 0.95])
plt.savefig("rread_4k_p99_all_in_one_line.pdf")
plt.close()

print("Line plots by system generated and saved as rread_4k_p99_all_in_one_line.pdf.")
