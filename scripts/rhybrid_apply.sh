#!/usr/bin/env bash
# rhybrid_apply.sh — Sender-side behavior switcher
# Applies CC mode and pacing according to regime hint

set -euo pipefail

IFACE="ens5"
regime="${1:-SINGLE_OWNER}"

apply_single_owner() {
  echo "[R-HYBRID][SENDER] Switching to SINGLE_OWNER mode (DCTCP + high pacing)"
  sudo sysctl -w net.ipv4.tcp_congestion_control=dctcp >/dev/null
  sudo tc qdisc replace dev "$IFACE" root fq pacing 1
}

apply_shared() {
  echo "[R-HYBRID][SENDER] Switching to SHARED mode (CUBIC + conservative pacing)"
  sudo sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
  sudo tc qdisc replace dev "$IFACE" root fq pacing 1
}

case "$regime" in
  SINGLE_OWNER) apply_single_owner ;;
  SHARED)       apply_shared ;;
  *)
    echo "[R-HYBRID][SENDER] Unknown regime '$regime', ignoring."
    ;;
esac
