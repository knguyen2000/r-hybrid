import sys
import pandas as pd
import matplotlib.pyplot as plt

# ==============================
# Basic CSV Input
# ==============================
if len(sys.argv) < 2:
    print("Usage: python analyze_results.py net-experiments.csv")
    sys.exit(1)

csv = sys.argv[1] if len(sys.argv) > 1 else "results/net-experiments-latest.csv"

cols = [
    "exp","topo","cc","mtu","impair","load","duration_s",
    "ping_avg_ms","ping_mdev_ms","tcp_sum_gbps","tcp_retr",
    "udp_gbps","udp_loss_pct","udp_jitter_ms","cpu_client_pct",
    "app_ttfb_s","app_total_s","app_hls_avg_s","notes"
]

df_raw = pd.read_csv(csv, header=0, engine='python', index_col=False)

# Fix overflow from commas in notes if needed
if len(df_raw.columns) > len(cols):
    df_raw["notes"] = df_raw[df_raw.columns[len(cols)-1:]].astype(str).agg(" ".join, axis=1)
    df_raw = df_raw.iloc[:, :len(cols)]

df_raw.columns = cols

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

# ==============================
# 1) MTU effect
# ==============================
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
else:
    print("[!] Skipping MTU plot — no data found")

# ==============================
# 2) CC clean vs loss
# ==============================
cc_clean = df[(df.topo=="T1") & (df.mtu==1500) & (df.impair=="none")]
if not cc_clean.empty:
    plt.figure()
    cc_clean.groupby("cc")["tcp_sum_gbps"].mean().plot(kind="bar")
    finalize_chart("fig_cc.png", "CC vs throughput (clean network, T1, MTU1500)",
                   "TCP sum throughput (Gbps)")
else:
    print("[!] Skipping CC clean plot — no data found")

cc_loss  = df[(df.topo=="T1") & (df.mtu==1500) & (df.impair=="l1p")]
if not cc_loss.empty:
    plt.figure()
    cc_loss.groupby("cc")["tcp_sum_gbps"].mean().plot(kind="bar")
    finalize_chart("fig_cc_loss.png", "CC vs throughput (1% loss, T1, MTU1500)",
                   "TCP sum throughput (Gbps)")
else:
    print("[!] Skipping CC loss plot — no data found")

# ==============================
# 3) Impairments impact
# ==============================
imp_df = df[(df.topo=="T1") & (df.cc=="cubic") & (df.mtu==1500)]
if not imp_df.empty:
    plt.figure()
    for imp, g in imp_df.groupby("impair"):
        plt.bar(imp, g["tcp_sum_gbps"].mean())
    finalize_chart("fig_impair.png", "Impairments vs TCP throughput (T1, CUBIC, MTU1500)",
                   "TCP sum throughput (Gbps)")
else:
    print("[!] Skipping Impair plot — no data found")

# ==============================
# 4) Path comparison
# ==============================
path_df = df[(df.cc=="cubic") & (df.mtu==1500) & (df.impair=="none") & (df.exp.isin(["E1","E5","E6"]))]
if not path_df.empty:
    plt.figure()
    for topo, g in path_df.groupby("topo"):
        plt.bar(topo, g["ping_avg_ms"].mean())
    finalize_chart("fig_paths.png", "Path vs Latency (avg RTT)", "Ping avg (ms)")
else:
    print("[!] Skipping Path plot — no data found")

# ==============================
# 5) App QoE (E9-E11)
# ==============================
app_df = df[df.exp.isin(["E9","E10","E11"])]
if not app_df.empty:
    plt.figure()
    for exp, g in app_df.groupby("exp"):
        plt.bar(exp, g["app_ttfb_s"].mean())
    finalize_chart("fig_app_ttfb.png", "App TTFB (progressive download)", "seconds")

    plt.figure()
    for exp, g in app_df.groupby("exp"):
        plt.bar(exp, g["app_hls_avg_s"].mean())
    finalize_chart("fig_app.png", "HLS-like avg segment fetch time", "seconds/segment")
else:
    print("[!] Skipping App QoE plot — no data found")

# ==============================
# 6) R-Hybrid vs Baseline Comparison
# ==============================
rhybrid_df = df[df.cc == "rhybrid"]
baseline_df = df[(df.cc == "cubic") & (df.mtu == 1500) & (df.impair == "none")]

if not rhybrid_df.empty and not baseline_df.empty:
    means_rhybrid = rhybrid_df.groupby("topo")["tcp_sum_gbps"].mean()
    means_cubic   = baseline_df.groupby("topo")["tcp_sum_gbps"].mean()
    idx = range(len(means_rhybrid.index))
    width = 0.35

    plt.figure()
    plt.bar([i - width/2 for i in idx], means_cubic.reindex(means_rhybrid.index, fill_value=0).values,
            width=width, label="CUBIC")
    plt.bar([i + width/2 for i in idx], means_rhybrid.values, width=width, label="R-Hybrid")
    plt.xticks(idx, means_rhybrid.index)
    plt.legend()
    finalize_chart("fig_rhybrid.png", "CUBIC vs R-Hybrid (Throughput)", "Gbps")

    # Print stats to CI logs
    print("\n[R-HYBRID] Summary Throughput by topo:")
    print(rhybrid_df.groupby("topo")["tcp_sum_gbps"].describe())
elif not rhybrid_df.empty:
    # Fallback single bar plot if no baseline present
    plt.figure()
    rhybrid_df.groupby("topo")["tcp_sum_gbps"].mean().plot(kind="bar")
    finalize_chart("fig_rhybrid.png", "R-Hybrid Throughput", "Gbps")
    print("\n[R-HYBRID] Summary Throughput by topo:")
    print(rhybrid_df.groupby("topo")["tcp_sum_gbps"].describe())
else:
    print("[!] Skipping R-Hybrid plot — no data found")

print("\nPlots generated (where data existed).")
