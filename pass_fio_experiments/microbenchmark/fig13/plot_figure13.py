import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

# Set font sizes globally
plt.rcParams.update({
    'font.size': 10,
    'axes.titlesize': 12,
    'axes.labelsize': 12,
    'xtick.labelsize': 12,
    'ytick.labelsize': 12,
    'legend.fontsize': 8
})

# Load CSV files
pass_df = pd.read_csv('pass_timeseries_ref.csv')
spdk_df = pd.read_csv('thunderbolt_timeseries_ref.csv')

# Plot the time series
plt.figure(figsize=(6, 3))
plt.plot(spdk_df['Seconds'], spdk_df['Power (Watts)'], label='SPDK + Thunderbolt', linewidth=2, color='orange')
plt.plot(pass_df['Seconds'], pass_df['Power (Watts)'], label='PASS (Ours)', linewidth=2)




# Define stepped power cap line
max_time = max(pass_df['Seconds'].max(), spdk_df['Seconds'].max())

# Plot step lines: 400W -> 350W -> 300W
plt.hlines(400, 0, 120, colors='green', linestyles='dashed', label='Power budget')
plt.hlines(350, 120, 240, colors='green', linestyles='dashed')
plt.hlines(300, 240, 360, colors='green', linestyles='dashed')
plt.hlines(400, 360, 480, colors='green', linestyles='dashed')
plt.hlines(375, 480, max_time, colors='green', linestyles='dashed')

# Formatting
# plt.title('System Power Over Time')
plt.xlabel('Time (Seconds)')
plt.ylabel('Power (Watts)')
plt.xlim(0, 540)
plt.ylim(250, 450)
# plt.grid(True)
custom_lines = [
    
    Line2D([0], [0], color='green', linestyle='dashed', linewidth=1.5, label='Power budget'),
    Line2D([0], [0], color='#1f77b4', linewidth=2, label='PASS (Ours)'),
    Line2D([0], [0], color='orange', linewidth=2, label='SPDK + Thunderbolt')
]

plt.legend(handles=custom_lines, loc='lower left', fontsize=8)
plt.tight_layout()

# Save as PDF
plt.savefig('power_timeseries.pdf', format='pdf')
print("Saved plot as power_timeseries.pdf")
