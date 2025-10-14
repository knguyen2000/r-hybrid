apply_impairment() {
  local profile="$1"
  case "$profile" in
    none)
      sudo tc qdisc del dev ens5 root || true
      ;;
    delay_20ms)
      sudo tc qdisc replace dev ens5 root netem delay 20ms
      ;;
    loss_1pct)
      sudo tc qdisc replace dev ens5 root netem loss 1%
      ;;
    delay_jitter)
      sudo tc qdisc replace dev ens5 root netem delay 20ms 10ms distribution normal
      ;;
    dynamic_switch)
      sudo tc qdisc del dev ens5 root || true
      (sleep 60 && sudo tc qdisc replace dev ens5 root netem delay 20ms 10ms) &
      (sleep 120 && sudo tc qdisc del dev ens5 root) &
      ;;
  esac
}

set_cc_mode() {
  local mode="$1"
  if [[ "$mode" == "hybrid" ]]; then
    echo "Hybrid mode handled by receiver agent"
  else
    sudo sysctl -w net.ipv4.tcp_congestion_control="$mode"
  fi
}
