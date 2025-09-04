import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

# Set the style
plt.rcParams.update({
    'font.size': 12,
    'axes.titlesize': 14,
    'axes.labelsize': 14,
    'xtick.labelsize': 16,
    'ytick.labelsize': 16,
    'legend.fontsize': 14
})

# Directory of stored CSVs
outdir = Path("./data_csv")
rapl_csv = outdir / "rapl.csv"
mask_csv = outdir / "mask.csv"
bw_csv = outdir / "bandwidth.csv"

# --- Step 1: Read datasets back from CSV ---
rapl_data = pd.read_csv(rapl_csv)
mask_data = pd.read_csv(mask_csv)
bw_data = pd.read_csv(bw_csv)

# --- Step 2: Plot function ---
def plot_and_save(df, title, filename):
    plt.figure(figsize=(5, 3))
    plt.plot(df['Polling Interval'], df['P99 Latency (us)'], marker='o')
    plt.xlabel('Polling Interval')
    plt.ylabel('P99 Latency (us)')
    plt.grid(True)
    plt.xscale('log')
    plt.yscale('log')
    plt.title(title)
    plt.tight_layout()
    plt.savefig(filename)
    plt.close()

# --- Step 3: Generate plots ---
plot_and_save(rapl_data, 'RAPL: Polling Interval vs P99 Latency', 'pi_p99_latency_rapl.pdf')
plot_and_save(mask_data, 'Masking: Polling Interval vs P99 Latency', 'pi_p99_latency_masking.pdf')
plot_and_save(bw_data, 'Bandwidth: Polling Interval vs P99 Latency', 'pi_p99_latency_bandwidth.pdf')
