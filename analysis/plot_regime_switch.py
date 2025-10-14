import re
import matplotlib.pyplot as plt
import datetime

log_file = "results/exp_1/regime_detection.log"

timestamps = []
modes = []

with open(log_file) as f:
    for line in f:
        m = re.match(r"(.+) Regime: (\w+), switched to (.+)", line.strip())
        if m:
            t_str, regime, mode = m.groups()
            t = datetime.datetime.strptime(t_str, "%a %b %d %H:%M:%S %Z %Y")
            timestamps.append(t)
            modes.append(mode)

plt.figure(figsize=(10,4))
plt.step(timestamps, modes, where='post')
plt.xticks(rotation=45)
plt.title("Regime Switch Timeline")
plt.ylabel("CC Mode")
plt.tight_layout()
plt.savefig("regime_switch.png")
