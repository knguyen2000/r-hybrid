#!/usr/bin/env bash
# Receiver-Informed agent: infers regime and COMMANDS THE SENDER (client) to switch CC.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <TARGET_IP_TO_MONITOR> <SENDER_INSTANCE_ID>"
  exit 1
fi

TARGET_IP="$1"
# FIX: The Instance ID of the client (sender) to be controlled.
SENDER_INSTANCE_ID="$2"
LOG="/var/log/cc_switch_events.csv"
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Force the sender's initial state to the "good network" CC mode.
echo "Forcing sender's initial CC mode to dctcp"
aws ssm send-command \
  --instance-ids "$SENDER_INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "R-Hybrid Initial CC Set" \
  --parameters '{"commands":["sudo sysctl -w net.ipv4.tcp_congestion_control=dctcp"]}' \
  --region "$REGION" > /dev/null

BASELINE_RTT=$(ping -c 5 "$TARGET_IP" | awk -F'/' '/rtt/ {print $5}')
CURRENT_MODE="dctcp" # We know the initial state is dctcp.
START_TS=$(date +%s)
THRESHOLD=1.5  # RTT tail inflation threshold

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
  RTT_TAIL=$(ping -c 5 "$TARGET_IP" | awk -F'/' '/rtt/ {print $6}')
  LOSS=$(ping -c 5 "$TARGET_IP" | grep -oP '\d+(?=% packet loss)' | tail -n1)
  ratio=$(echo "$RTT_TAIL / $BASELINE_RTT" | bc -l)
  NEW_MODE="$CURRENT_MODE"

  # Heuristic: if RTT is inflated OR there's packet loss, switch to robust mode.
  if (( $(echo "$ratio > $THRESHOLD" | bc -l) )) || [[ "$LOSS" -gt 0 ]]; then
    NEW_MODE="cubic"
  else
    NEW_MODE="dctcp"
  fi

  if [[ "$NEW_MODE" != "$CURRENT_MODE" ]]; then
    # Command the SENDER to change its CC.
    echo "Regime change detected. Commanding sender ($SENDER_INSTANCE_ID) to switch to $NEW_MODE"
    aws ssm send-command \
      --instance-ids "$SENDER_INSTANCE_ID" \
      --document-name "AWS-RunShellScript" \
      --comment "R-Hybrid CC Switch" \
      --parameters "{\"commands\":[\"sudo sysctl -w net.ipv4.tcp_congestion_control=$NEW_MODE\"]}" \
      --region "$REGION" > /dev/null

    log_switch "$NEW_MODE"
    CURRENT_MODE="$NEW_MODE"
    START_TS=$(date +%s)
  fi
  sleep 2
done