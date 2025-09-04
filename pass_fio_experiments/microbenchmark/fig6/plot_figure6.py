import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

# --- Load CSV ---
csv_path = "latency_ref.csv"
df = pd.read_csv(csv_path)

# Ensure desired power order (matches your original list)
power_budgets = [280, 290, 350, 440, 480]
df["power"] = pd.Categorical(df["power"], categories=power_budgets, ordered=True)

# Systems in desired legend order (short names now)
systems = ["pass", "ssd_bw_only", "cpu_bw_only", "cpu_jailing_only", "rapl_only"]

# --- Normalize p99 latencies to pass at each power ---
base = df[df["system"] == "pass"][["power", "p99 latency"]].rename(columns={"p99 latency": "base_p99"})
merged = df.merge(base, on="power", how="left")

merged["normalized"] = merged.apply(
    lambda r: (r["p99 latency"] / r["base_p99"]) if pd.notna(r["p99 latency"]) and pd.notna(r["base_p99"]) and r["base_p99"] != 0
    else np.nan,
    axis=1
)

# Keep plotting order
merged = merged[merged["system"].isin(systems)].copy()
merged["system"] = pd.Categorical(merged["system"], categories=systems, ordered=True)

# --- Plotting ---
bar_width = 0.2
x = np.arange(len(power_budgets))

colors = ['tab:blue', 'tab:orange', 'tab:green', 'tab:red', 'tab:purple']
hatches = ['', '//', '\\\\', 'xx', '..']

fig, ax = plt.subplots(figsize=(5, 2.9))

for idx, system in enumerate(systems):
    offset = (idx - len(systems) / 2) * bar_width + bar_width / 2
    vals = (
        merged[merged["system"] == system]
        .sort_values("power")["normalized"]
        .tolist()
    )
    bars = ax.bar(
        x + offset,
        [v if pd.notna(v) else 0 for v in vals],
        bar_width,
        label=system,
        color=colors[idx],
        hatch=hatches[idx]
    )

    # Optional: show hollow bars for missing data
    # for i, v in enumerate(vals):
    #     if pd.isna(v):
    #         bars[i].set_facecolor("white")
    #         bars[i].set_edgecolor(colors[idx])
    #         bars[i].set_linewidth(1.5)

ax.set_xlabel("Power Budget (W)", fontsize=14)
ax.set_ylabel("Normalized P99 Latency", fontsize=14)
ax.set_ylim(0, 2.5)
ax.set_xticks(x)
ax.set_xticklabels([f"{p}W" for p in power_budgets])
ax.legend(fontsize=9)

plt.tight_layout()
plt.savefig("normalized_p99_latency_ablation_study.pdf", dpi=300)
# plt.show()
