#!/usr/bin/env bash
# Receiver-side agent: infers regime and switches CC
set -euo pipefail

SERVER_IP="$1"
LOG="/var/log/cc_switch_events.csv"
BASELINE_RTT=$(ping -c 5 $SERVER_IP | awk -F'/' '/rtt/ {print $5}')
CURRENT_MODE=$(sysctl -n net.ipv4.tcp_congestion_control)
START_TS=$(date +%s)
THRESHOLD=1.2  # RTT tail inflation threshold

if [[ ! -f "$LOG" ]]; then
  echo "timestamp,experiment,cc_mode,duration_s" | sudo tee -a "$LOG" >/dev/null
fi

log_switch() {
  local new_mode="$1"
  local now=$(date +%s)
  local dur=$(( now - START_TS ))
  echo "$(date -Is),R-Hybrid,$new_mode,$dur" | sudo tee -a "$LOG" >/dev/null
}

while true; do
  RTT_TAIL=$(ping -c 5 $SERVER_IP | awk -F'/' '/rtt/ {print $6}')
  LOSS=$(ping -c 5 $SERVER_IP | grep -oP '\d+(?=% packet loss)' | tail -n1)
  ratio=$(echo "$RTT_TAIL / $BASELINE_RTT" | bc -l)
  NEW_MODE="$CURRENT_MODE"

  if (( $(echo "$ratio < $THRESHOLD" | bc -l) )) && [[ "$LOSS" -eq 0 ]]; then
    NEW_MODE="dctcp"
  else
    NEW_MODE="cubic"
  fi

  if [[ "$NEW_MODE" != "$CURRENT_MODE" ]]; then
    sysctl -w net.ipv4.tcp_congestion_control="$NEW_MODE" >/dev/null
    log_switch "$NEW_MODE"
    CURRENT_MODE="$NEW_MODE"
    START_TS=$(date +%s)
  fi
  sleep 2
done
