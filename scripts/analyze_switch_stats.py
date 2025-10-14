#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt
import os

CSV_PATH = "results/cc_switch_events.csv"
if not os.path.isfile(CSV_PATH):
    print(f"[!] No switch events found: {CSV_PATH}")
    exit(0)

df = pd.read_csv(CSV_PATH)
df["duration_s"] = pd.to_numeric(df["duration_s"], errors="coerce")

summary_mode = df.groupby("cc_mode")["duration_s"].agg(["count","mean","sum"]).reset_index()
summary_mode.rename(columns={"count":"num_intervals","mean":"avg_duration_s","sum":"total_duration_s"}, inplace=True)

print("\n=== Dwell Time by CC Mode ===")
print(summary_mode.to_string(index=False))

switch_counts = df.groupby("experiment").size().reset_index(name="num_switches")
dwell_time_per_exp = df.groupby("experiment")["duration_s"].sum().reset_index(name="total_time_s")
summary_exp = switch_counts.merge(dwell_time_per_exp, on="experiment", how="left")
print("\n=== Switching Frequency per Experiment ===")
print(summary_exp.to_string(index=False))

plot_dir = "results/plots"
os.makedirs(plot_dir, exist_ok=True)

plt.figure(figsize=(8,4))
plt.bar(summary_mode["cc_mode"], summary_mode["total_duration_s"])
plt.title("Total Dwell Time per CC Mode")
plt.ylabel("Total Duration (s)")
plt.savefig(os.path.join(plot_dir, "dwell_time_per_mode.png"))

plt.figure(figsize=(10,5))
plt.bar(summary_exp["experiment"], summary_exp["num_switches"])
plt.xticks(rotation=45, ha="right")
plt.title("Switching Frequency per Experiment")
plt.ylabel("Number of Switches")
plt.savefig(os.path.join(plot_dir, "switch_count_per_experiment.png"))

summary_mode.to_csv(os.path.join(plot_dir,"summary_dwell_time_by_mode.csv"), index=False)
summary_exp.to_csv(os.path.join(plot_dir,"summary_switch_frequency_by_experiment.csv"), index=False)

print(f"[+] Exported results to {plot_dir}/")
