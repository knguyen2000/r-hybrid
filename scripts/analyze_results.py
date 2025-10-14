import sys
import pandas as pd
import matplotlib.pyplot as plt

if len(sys.argv) < 2:
    print("Usage: python analyze_results.py net-experiments.csv")
    sys.exit(1)

csv = sys.argv[1]
df_raw = pd.read_csv(csv, header=0, engine='python', index_col=False)

# Determine if short_label is present
expected_cols = [
    "exp","short_label","topo","cc","mtu","impair","load","duration_s",
    "ping_avg_ms","ping_mdev_ms","tcp_sum_gbps","tcp_retr",
    "udp_gbps","udp_loss_pct","udp_jitter_ms","cpu_client_pct",
    "app_ttfb_s","app_total_s","app_hls_avg_s","notes"
]

legacy_cols = [
    "exp","topo","cc","mtu","impair","load","duration_s",
    "ping_avg_ms","ping_mdev_ms","tcp_sum_gbps","tcp_retr",
    "udp_gbps","udp_loss_pct","udp_jitter_ms","cpu_client_pct",
    "app_ttfb_s","app_total_s","app_hls_avg_s","notes"
]

if len(df_raw.columns) >= len(expected_cols):
    df_raw.columns = expected_cols
else:
    df_raw.columns = legacy_cols
    df_raw["short_label"] = df_raw["exp"]  # fallback to exp ID

# Trim string columns
df = df_raw.apply(lambda x: x.str.strip() if x.dtype == "object" else x)

# Clean up mdev suffix if present
df["ping_mdev_ms"] = df["ping_mdev_ms"].astype(str).str.replace(" ms","",regex=False)

# Convert numerics
num_cols = ["duration_s","ping_avg_ms","ping_mdev_ms","tcp_sum_gbps","tcp_retr",
            "udp_gbps","udp_loss_pct","udp_jitter_ms","cpu_client_pct",
            "app_ttfb_s","app_total_s","app_hls_avg_s"]
df[num_cols] = df[num_cols].apply(pd.to_numeric, errors="coerce")

print(df.head(3).to_string())
print("Unique topo values:", df["topo"].unique())

# Helper for nicer charts
def finalize_chart(filename, title=None, ylabel=None, xlabel=None):
    if title: plt.title(title)
    if ylabel: plt.ylabel(ylabel)
    if xlabel: plt.xlabel(xlabel)
    plt.grid(axis='y', linestyle='--', alpha=0.5)
    plt.tight_layout()
    plt.savefig(filename, bbox_inches="tight")
    plt.close()

# MTU effect
mtu_df = df[(df.topo=="T1") & (df.cc=="cubic") & (df.impair=="none")]
if not mtu_df.empty:
    plt.figure()
    labels, vals = [], []
    for mtu, g in mtu_df.groupby("mtu"):
        labels.append(str(mtu))
        vals.append(g["tcp_sum_gbps"].mean())
    plt.bar(labels, vals)
    finalize_chart("fig_mtu.png", "MTU effect on TCP throughput (T1, CUBIC, no impair)",
                   "TCP sum throughput (Gbps)", "MTU")

# CC clean vs loss
cc_clean = df[(df.topo=="T1") & (df.mtu==1500) & (df.impair=="none")]
if not cc_clean.empty:
    plt.figure()
    cc_clean.groupby("cc")["tcp_sum_gbps"].mean().plot(kind="bar")
    finalize_chart("fig_cc.png", "CC vs throughput (clean network, T1, MTU1500)",
                   "TCP sum throughput (Gbps)")

cc_loss  = df[(df.topo=="T1") & (df.mtu==1500) & (df.impair=="l1p")]
if not cc_loss.empty:
    plt.figure()
    cc_loss.groupby("cc")["tcp_sum_gbps"].mean().plot(kind="bar")
    finalize_chart("fig_cc_loss.png", "CC vs throughput (1% loss, T1, MTU1500)",
                   "TCP sum throughput (Gbps)")

# Impairments impact
imp_df = df[(df.topo=="T1") & (df.cc=="cubic") & (df.mtu==1500)]
if not imp_df.empty:
    plt.figure()
    for imp, g in imp_df.groupby("impair"):
        plt.bar(imp, g["tcp_sum_gbps"].mean())
    finalize_chart("fig_impair.png", "Impairments vs TCP throughput (T1, CUBIC, MTU1500)",
                   "TCP sum throughput (Gbps)")

# Path comparison
path_df = df[(df.cc=="cubic") & (df.mtu==1500) & (df.impair=="none") & (df.exp.isin(["E1","E3","E4"]))]
if not path_df.empty:
    plt.figure()
    for topo, g in path_df.groupby("topo"):
        plt.bar(topo, g["ping_avg_ms"].mean())
    finalize_chart("fig_paths.png", "Path vs Latency (avg RTT)", "Ping avg (ms)")

# App QoE
app_df = df[df.short_label.isin(["cubic_http","cubic_hls_loss"])]
if not app_df.empty:
    plt.figure()
    for label, g in app_df.groupby("short_label"):
        plt.bar(label, g["app_ttfb_s"].mean())
    finalize_chart("fig_app_ttfb.png", "App TTFB (progressive download)", "seconds")

    plt.figure()
    for label, g in app_df.groupby("short_label"):
        plt.bar(label, g["app_hls_avg_s"].mean())
    finalize_chart("fig_app.png", "HLS-like avg segment fetch time", "seconds/segment")

# Plots for short_label / ECN / Hybrid
# Grouped throughput by short_label (full experiment set)
plt.figure(figsize=(10,5))
df.groupby("short_label")["tcp_sum_gbps"].mean().sort_values(ascending=False).plot(kind="bar")
finalize_chart("fig_shortlabel_throughput.png", "Throughput by Experiment Label", "Gbps", "short_label")

# Boxplot by short_label (to see variance)
plt.figure(figsize=(12,6))
df.boxplot(column="tcp_sum_gbps", by="short_label", rot=90)
plt.suptitle("")
finalize_chart("fig_shortlabel_boxplot.png", "Throughput Distribution by Label", "Gbps", "short_label")

# R-Hybrid vs Baselines (CUBIC / BBR / DCTCP) — aggregated
compare_labels = ["cubic_base","bbr_base","dctcp_clean","rhybrid_base"]
cmp_df = df[df.short_label.isin(compare_labels)]
if not cmp_df.empty:
    plt.figure()
    cmp_df.groupby("short_label")["tcp_sum_gbps"].mean().plot(kind="bar")
    finalize_chart("fig_cc_rhybrid_baseline.png", "Baseline vs R-Hybrid Throughput", "Gbps")

# ECN vs no-ECN: DCTCP vs CUBIC under ECN200M
ecn_labels = ["dctcp_clean","dctcp_ecn200","cubic_ecn200"]
ecn_df = df[df.short_label.isin(ecn_labels)]
if not ecn_df.empty:
    plt.figure()
    ecn_df.groupby("short_label")["tcp_sum_gbps"].mean().plot(kind="bar")
    finalize_chart("fig_ecn_vs_none.png", "ECN vs Non-ECN (DCTCP/CUBIC)", "Gbps")

# R-Hybrid ECN behavior
hyb_ecn = df[df.short_label.isin(["rhybrid_base","rhybrid_ecn200"])]
if not hyb_ecn.empty:
    plt.figure()
    hyb_ecn.groupby("short_label")["tcp_sum_gbps"].mean().plot(kind="bar")
    finalize_chart("fig_rhybrid_ecn.png", "R-Hybrid Throughput under ECN vs Clean", "Gbps")

print("\n Plots generated")
