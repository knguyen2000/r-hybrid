set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <SERVER_PRIVATE_IP>"
  exit 1
fi
SERVER_IP="$1"
CSV="/var/log/net-experiments.csv"
DUR=10
PAR=4
UDP_RATE="1G"
HTTP_URL_BIG="http://${SERVER_IP}/big.bin"
HLS_URL_PREFIX="http://${SERVER_IP}/hls/seg"
HLS_SEG_COUNT=10

# tools
sudo yum install -y iperf3 iproute-tc jq sysstat curl awscli >/dev/null 2>&1 || true

IFACE="ens5"

cc_get() { sysctl -n net.ipv4.tcp_congestion_control; }
cc_set() { sudo sysctl -w net.ipv4.tcp_congestion_control="$1" >/dev/null; }
mtu_set() { sudo ip link set dev "$IFACE" mtu "$1"; }

impair_clear() { sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true; }
impair_set() {
  local delay="$1" loss="$2"
  impair_clear
  if [[ "$delay" != "0" || "$loss" != "0" ]]; then
    sudo tc qdisc add dev "$IFACE" root netem ${delay:+delay $delay} ${loss:+loss $loss}
  fi
}

cpu_sample() { mpstat 1 3 | awk '/Average:/ && $3 ~ /all/ {print 100-$12}'; }

ping_block() {
  ping -c 20 "$SERVER_IP" | tee /tmp/ping.txt >/dev/null
  AVG=$(awk -F'/' '/rtt/ {print $5}' /tmp/ping.txt)
  MDEV=$(awk -F'/' '/rtt/ {print $7}' /tmp/ping.txt)
  echo "$AVG"  > /tmp/ping_avg
  echo "$MDEV" > /tmp/ping_mdev
}

iperf_tcp() {
  iperf3 -c "$SERVER_IP" -p 5001 -P "$PAR" -t "$DUR" --json > /tmp/iperf_tcp.json
  jq -r '.end.sum_received.bits_per_second' /tmp/iperf_tcp.json | awk '{printf "%.2f", $1/1e9}' > /tmp/tcp_gbps
  jq -r '[.end.streams[].sender.retransmits] | add' /tmp/iperf_tcp.json > /tmp/tcp_retr
}

iperf_udp() {
  iperf3 -c "$SERVER_IP" -p 5001 -u -b "$UDP_RATE" -t "$DUR" --json > /tmp/iperf_udp.json
  jq -r '.end.sum.bits_per_second' /tmp/iperf_udp.json | awk '{printf "%.2f", $1/1e9}' > /tmp/udp_gbps
  jq -r '.end.sum.lost_percent' /tmp/iperf_udp.json | awk '{printf "%.2f", $1}' > /tmp/udp_loss
  jq -r '.end.sum.jitter_ms' /tmp/iperf_udp.json | awk '{printf "%.3f", $1}' > /tmp/udp_jitter
}

app_progressive() {
  curl -s -w "%{time_starttransfer} %{time_total}\n" -o /dev/null "$HTTP_URL_BIG" > /tmp/app_progressive.txt
}

app_hls_loop() {
  > /tmp/app_hls_times.txt
  for i in $(seq -w 1 "$HLS_SEG_COUNT"); do
    /usr/bin/time -f "%e" curl -s -o /dev/null "${HLS_URL_PREFIX}${i}.ts" 2>> /tmp/app_hls_times.txt
  done
  awk '{s+=$1} END{if(NR>0) printf "%.3f", s/NR; else print "0.000"}' /tmp/app_hls_times.txt > /tmp/app_hls_avg
}

bottleneck_clear() { sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true; }

bottleneck_ecn() {
  local MAXRATE="$1"     # e.g. 200Mbit
  local CE_T="$2"        # e.g. 300us
  bottleneck_clear
  sudo tc qdisc replace dev "$IFACE" root fq maxrate "$MAXRATE" ce_threshold "$CE_T"
}

bottleneck_fqcodel_ecn() {
  local LIMIT_PKTS="${1:-1000}"
  bottleneck_clear
  sudo tc qdisc replace dev "$IFACE" root fq_codel ecn limit "$LIMIT_PKTS"
}

csv_header() {
  if [[ ! -f "$CSV" ]]; then
    echo "exp,short_label,topo,cc,mtu,impair,load,duration_s,ping_avg_ms,ping_mdev_ms,tcp_sum_gbps,tcp_retr,udp_gbps,udp_loss_pct,udp_jitter_ms,cpu_client_pct,app_ttfb_s,app_total_s,app_hls_avg_s,notes" | sudo tee -a "$CSV" >/dev/null
  fi
}

record() {
  local exp="$1" label="$2" topo="$3" cc="$4" mtu="$5" impair="$6" load="$7" notes="$8"
  local PING_AVG=$(cat /tmp/ping_avg 2>/dev/null || echo "")
  local PING_MDEV=$(cat /tmp/ping_mdev 2>/dev/null || echo "")
  local TCP_G=$(cat /tmp/tcp_gbps 2>/dev/null || echo "")
  local TCP_R=$(cat /tmp/tcp_retr 2>/dev/null || echo "")
  local UDP_G=$(cat /tmp/udp_gbps 2>/dev/null || echo "")
  local UDP_L=$(cat /tmp/udp_loss 2>/dev/null || echo "")
  local UDP_J=$(cat /tmp/udp_jitter 2>/dev/null || echo "")
  local CPU=$(cpu_sample)
  local TTFB=$(awk '{print $1}' /tmp/app_progressive.txt 2>/dev/null || echo "")
  local ATOT=$(awk '{print $2}' /tmp/app_progressive.txt 2>/dev/null || echo "")
  local HLSA=$(cat /tmp/app_hls_avg 2>/dev/null || echo "")
  printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%.1f,%s,%s,%s,%s\n" \
    "$exp" "$label" "$topo" "$cc" "$mtu" "$impair" "$load" "$DUR" \
    "$PING_AVG" "$PING_MDEV" "$TCP_G" "$TCP_R" "$UDP_G" "$UDP_L" "$UDP_J" "$CPU" "$TTFB" "$ATOT" "$HLSA" "$notes" \
    | sudo tee -a "$CSV" >/dev/null
}

csv_header

run_bundle() {
  local EXP="$1" LABEL="$2" TOPO="$3" CC="$4" MTU="$5" IMP="$6" LOAD="$7" NOTES="$8" BOTTLENECK="${9:-none}"
  echo "[*] $EXP: $LABEL topo=$TOPO cc=$CC mtu=$MTU impair=$IMP bottleneck=$BOTTLENECK"

  cc_set "$CC"
  mtu_set "$MTU"

  case "$BOTTLENECK" in
    none) bottleneck_clear ;;
    ecn200m) bottleneck_ecn "200Mbit" "300us" ;;
    fqcodel) bottleneck_fqcodel_ecn "2000" ;;
    *) bottleneck_clear ;;
  esac

  case "$IMP" in
    none) impair_set 0 0 ;;
    l1p) impair_set 0 1% ;;
  esac

  ping_block
  iperf_tcp
  iperf_udp

  if [[ "$EXP" =~ ^E(7|8)$ ]]; then
    app_progressive
    [[ "$EXP" == "E8" ]] && app_hls_loop || true
  else
    : > /tmp/app_progressive.txt || true
    : > /tmp/app_hls_avg || true
  fi

  record "$EXP" "$LABEL" "$TOPO" "$CC" "$MTU" "$IMP" "$LOAD" "$NOTES"
  impair_clear
  bottleneck_clear
}

# Core Baseline (E1–E8)
run_bundle E1 "cubic_base"     T1 cubic   1500 none none "baseline same-AZ private, CUBIC"
run_bundle E2 "bbr_base"       T1 bbr     1500 none none "BBR vs CUBIC"
run_bundle E3 "cubic_crossAZ"  T2 cubic   1500 none none "cross-AZ (shared path)"
run_bundle E4 "cubic_igw"      T3 cubic   1500 none none "public-path via IGW"
run_bundle E5 "cubic_loss"     T1 cubic   1500 l1p  none "CUBIC under 1% loss"
run_bundle E6 "bbr_loss"       T1 bbr     1500 l1p  none "BBR under 1% loss"
run_bundle E7 "cubic_http"     T1 cubic   1500 none none "HTTP big.bin"
run_bundle E8 "cubic_hls_loss" T1 cubic   1500 l1p  none "HLS-like under 1% loss"

# Dynamic Regime Shift (E9–E12)
run_bundle E9  "rhybrid_base"  T1 rhybrid 1500 none none "R-Hybrid adaptive switching"
run_bundle E10 "cubic_loss_react"  T1 cubic   1500 l1p none "CUBIC under loss"
run_bundle E11 "bbr_loss_react"    T1 bbr     1500 l1p none "BBR under loss"
run_bundle E12 "rhybrid_loss_flip" T1 rhybrid 1500 l1p none "R-Hybrid under loss (should switch)"

# DCTCP + ECN (E13–E17)
run_bundle E13 "dctcp_clean"    T1 dctcp   1500 none none "DCTCP clean (no ECN bottleneck)" none
run_bundle E14 "dctcp_ecn200"   T1 dctcp   1500 none none "DCTCP + ECN bottleneck 200Mbit" ecn200m
run_bundle E15 "cubic_ecn200"   T1 cubic   1500 none none "CUBIC + ECN bottleneck 200Mbit (control)" ecn200m
run_bundle E16 "dctcp_fqcodel"  T1 dctcp   1500 none none "DCTCP + ECN fq_codel bottleneck" fqcodel
run_bundle E17 "rhybrid_ecn200" T1 rhybrid 1500 none none "R-Hybrid + ECN bottleneck 200Mbit (expected DCTCP)" ecn200m

echo "Done. CSV at: $CSV"

if [[ -n "${RESULT_S3_URI:-}" ]]; then
  TS=$(date +%Y%m%d-%H%M%S)
  /usr/bin/aws s3 cp "$CSV" "${RESULT_S3_URI%/}/net-experiments-$TS.csv"
  echo "Uploaded results to ${RESULT_S3_URI%/}/net-experiments-$TS.csv"
fi
