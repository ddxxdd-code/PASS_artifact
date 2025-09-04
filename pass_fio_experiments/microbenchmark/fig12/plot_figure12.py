import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# Load the data
data = pd.read_csv('latency_ref.csv')

# Set font sizes globally
plt.rcParams.update({
    'font.size': 12,       # Base font size
    'axes.titlesize': 16,  # Title size
    'axes.labelsize': 16,  # Axis label size
    'xtick.labelsize': 16, # X-axis tick size
    'ytick.labelsize': 16, # Y-axis tick size
    'legend.fontsize': 12  # Legend font size
})

# Define styles for methods
method_map = {"thunderbolt": "SPDK + Thunderbolt", "pass": "PASS (Ours)"}
styles = {
    "pass": {"color": "#1f77b4", "marker": "o", "linestyle": "-"},
    "thunderbolt": {"color": "#ff7f0e", "marker": "s", "linestyle": "--"}
}

# Plotting
plt.figure(figsize=(8, 4.5))

for method in ["pass", "thunderbolt"]:
    method_data = data[data["system"] == method]
    style = styles.get(method, {"color": "#000000", "marker": "x", "linestyle": ":"})
    plt.plot(
        method_data["power"],
        method_data["p99 latency"],
        label=method_map[method],
        color=style["color"],
        marker=style["marker"],
        linestyle=style["linestyle"],
        markersize=10, 
        linewidth=2
    )

# Set log scale for y-axis
plt.yscale('log')

# Add labels, title, and legend
plt.xlabel("Power budget (W)")
plt.ylabel("p99 Latency (us)")
plt.xlim(240,450)
# plt.xlim(240,380)
# plt.title("p99 Tail Latency vs. Power Budget")
plt.legend()
plt.grid(visible=True, which="both", linestyle="--", linewidth=0.5, alpha=0.7)

# Save the figure
plt.tight_layout()
plt.savefig("rread_4k_isolation_of_performance.pdf")

print("Line graph with different markers and line styles saved as rread_4k_isolation_of_performance.pdf.")
