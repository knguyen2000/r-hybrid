set -euo pipefail

IFACE="ens5"
regime="${1:-SINGLE_OWNER}"

cleanup_qdisc() {
  sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
}

apply_single_owner() {
  echo "[R-HYBRID][SENDER] Switching to SINGLE_OWNER mode (DCTCP + high pacing)"
  cleanup_qdisc
  sudo sysctl -w net.ipv4.tcp_congestion_control=dctcp >/dev/null
  sudo sysctl -w net.ipv4.tcp_ecn=1 >/dev/null
  sudo tc qdisc replace dev "$IFACE" root fq pacing 1
}

apply_shared() {
  echo "[R-HYBRID][SENDER] Switching to SHARED mode (CUBIC + conservative pacing)"
  cleanup_qdisc
  sudo sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
  sudo sysctl -w net.ipv4.tcp_ecn=1 >/dev/null   # ECN stays on (optional)
  sudo tc qdisc replace dev "$IFACE" root fq pacing 1
}

# Apply the regime
case "$regime" in
  SINGLE_OWNER) apply_single_owner ;;
  SHARED)       apply_shared ;;
  *)
    echo "[R-HYBRID][SENDER] Unknown regime '$regime', ignoring."
    ;;
esac

# Verification output for debugging
current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
current_ecn=$(sysctl -n net.ipv4.tcp_ecn)
echo "[R-HYBRID][SENDER] Current CC mode: $current_cc | ECN: $current_ecn"
