import pandas as pd
import matplotlib.pyplot as plt

# Set font sizes globally
plt.rcParams.update({
    'font.size': 12,       # Base font size
    'axes.titlesize': 14,  # Title size
    'axes.labelsize': 14,  # Axis label size
    'xtick.labelsize': 16, # X-axis tick size
    'ytick.labelsize': 16, # Y-axis tick size
    'legend.fontsize': 12  # Legend font size
})

# Read data from CSV
df = pd.read_csv("power_breakdown_ref.csv")

# Plot
fig, ax = plt.subplots(figsize=(8, 4.5))
x_indices = range(len(df['system_power']),0,-1)  # Use integer indices for x-axis
x_labels = df['system_power']  # Original labels
bar_width = 0.8

cpu_bar = ax.bar(x_indices, df['cpu_power'], bottom=df['disk_power'] + df['other_power'], color='#1f77b4', hatch='//', label='CPU Power', width=bar_width)
disk_bar = ax.bar(x_indices, df['disk_power'], bottom=df['other_power'], color='#ff7f0e', hatch='\\\\', label='Disk Power', width=bar_width)
other_bar = ax.bar(
    x_indices, df['other_power'],
    color='#2ca02c', hatch='--', label='Others Power', width=bar_width
)

# Customizations
ax.set_xlabel("Power Budget (W)")
ax.set_ylabel("Power (W)")
ax.set_xticks(x_indices)  # Set integer indices as ticks
ax.set_xticklabels(x_labels)
# ax.set_title("System Power Breakdown")
ax.legend()

# Show the plot
plt.tight_layout()
plt.savefig("swrite_128k_power_breakdown.pdf", bbox_inches='tight')
