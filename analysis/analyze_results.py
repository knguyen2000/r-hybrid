import os
import glob
import pandas as pd
import matplotlib.pyplot as plt

def parse_iperf_logs(results_dir):
    data = []
    for exp in sorted(os.listdir(results_dir)):
        logs = glob.glob(f"{results_dir}/{exp}/iperf_*.log")
        if not logs:
            continue
        for log in logs:
            with open(log) as f:
                for line in f:
                    if "sender" in line and "Mbits/sec" in line:
                        parts = line.strip().split()
                        data.append({
                            "exp": exp,
                            "throughput": float(parts[-2]),
                            "unit": parts[-1]
                        })
    return pd.DataFrame(data)

def plot_throughput(df):
    df.groupby("exp")["throughput"].mean().plot(kind='bar', figsize=(12,5))
    plt.ylabel("Mbps")
    plt.title("Throughput per Experiment")
    plt.tight_layout()
    plt.savefig("throughput_summary.png")

if __name__ == "__main__":
    df = parse_iperf_logs("../scripts/results")
    if not df.empty:
        plot_throughput(df)
        print(df.groupby("exp")["throughput"].mean())
    else:
        print("No iperf data found.")
