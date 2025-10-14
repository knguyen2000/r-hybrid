#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="$1"
LOG_FILE="/var/log/regime_detection.log"
IFACE="ens5"

detect_regime() {
    ping -c 20 "$SERVER_IP" > /tmp/ping_r.txt
    RTT_P99=$(awk -F'/' '/rtt/ {print $7}' /tmp/ping_r.txt)
    RTT_P50=$(awk -F'/' '/rtt/ {print $5}' /tmp/ping_r.txt)
    TAIL_DIFF=$(echo "$RTT_P99 - $RTT_P50" | bc)

    ECN=$(cat /proc/net/netstat | grep -m1 TcpExt | awk '{print $25}')
    sleep 1
    ECN_AFTER=$(cat /proc/net/netstat | grep -m1 TcpExt | awk '{print $25}')
    ECN_DIFF=$((ECN_AFTER - ECN))

    LOSS=$(awk -F'[, ]+' '/packet loss/ {print $7}' /tmp/ping_r.txt | tr -d '%')

    if (( $(echo "$TAIL_DIFF < 5.0" | bc -l) )) && [ "$ECN_DIFF" -eq 0 ] && (( $(echo "$LOSS < 0.1" | bc -l) )); then
        echo "SINGLE_OWNER" > /tmp/regime
    else
        echo "SHARED" > /tmp/regime
    fi
}

switch_cc_mode() {
    local regime=$(cat /tmp/regime)
    current=$(sysctl -n net.ipv4.tcp_congestion_control)
    if [[ "$regime" == "SINGLE_OWNER" && "$current" != "dctcp" ]]; then
        sudo sysctl -w net.ipv4.tcp_congestion_control=dctcp
        echo "$(date) Regime: $regime, switched to DCTCP" >> "$LOG_FILE"
    elif [[ "$regime" == "SHARED" && "$current" != "cubic" ]]; then
        sudo sysctl -w net.ipv4.tcp_congestion_control=cubic
        echo "$(date) Regime: $regime, switched to CUBIC" >> "$LOG_FILE"
    fi
}

while true; do
    detect_regime
    switch_cc_mode
    sleep 30
done
