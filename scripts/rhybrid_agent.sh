set -euo pipefail

IFACE="ens5"
SENDER_TAG="network-test-client"
TARGET_IP_FILE="/tmp/rhybrid_target_ip"
REGIME_FILE="/tmp/rhybrid_regime"
BASELINE_FILE="/tmp/rhybrid_baseline_rtt"
WINDOW_SEC=5                   # interval between samples
HISTORY_SIZE=5                 # number of samples to keep (sliding window)
THRESH_RTT=5                   # ms above baseline to count as congestion
THRESH_ECN=1                   
THRESH_RETR=1                  
REQUIRED_CONSEC=3              # require M consecutive detections before flipping
COOLDOWN_SEC=15                # minimum time between flips (seconds)
PING_COUNT=20

# Target IP (client)
if [[ $# -ge 1 ]]; then
  TARGET_IP="$1"
else
  TARGET_IP=$(ip route | awk '/default/ {print $3; exit}')
fi
echo "$TARGET_IP" > "$TARGET_IP_FILE"

# Baseline RTT measurement
baseline_rtt=$(ping -c 5 "$TARGET_IP" | awk -F'/' '/rtt/ {print $5}')
if [[ -z "$baseline_rtt" ]]; then
  baseline_rtt=0
fi
echo "$baseline_rtt" > "$BASELINE_FILE"
echo "[R-HYBRID] Baseline RTT to $TARGET_IP = $baseline_rtt ms"

# State variables
echo "UNKNOWN" > "$REGIME_FILE"
declare -a rtt_hist ecn_hist retr_hist
history_idx=0
flip_cooldown_until=0
last_regime="UNKNOWN"
consec_count=0

get_time() { date +%s; }

get_ecn_ce() {
  grep TcpExtECNRecvCE /proc/net/netstat | awk '{print $2}' || echo 0
}

get_retrans() {
  ss -ti | awk '/retrans:/ {gsub(/retrans:/,""); s+=$2} END{print s+0}'
}

# Sliding window update
update_history() {
  local rtt_val="$1" ecn_val="$2" retr_val="$3"
  rtt_hist[$history_idx]="$rtt_val"
  ecn_hist[$history_idx]="$ecn_val"
  retr_hist[$history_idx]="$retr_val"
  history_idx=$(( (history_idx + 1) % HISTORY_SIZE ))
}

# Compute congestion score based on history
compute_score() {
  local congest_count=0
  local base=$(cat "$BASELINE_FILE")
  for i in "${!rtt_hist[@]}"; do
    # if no history yet, skip
    if [[ -z "${rtt_hist[$i]:-}" ]]; then continue; fi
    local rtt=${rtt_hist[$i]}
    local ecn=${ecn_hist[$i]}
    local retr=${retr_hist[$i]}
    local congest=0

    if (( $(echo "$rtt > $base + $THRESH_RTT" | bc -l) )); then congest=1; fi
    if (( ecn > THRESH_ECN )); then congest=1; fi
    if (( retr > THRESH_RETR )); then congest=1; fi

    (( congest_count += congest ))
  done
  echo "$congest_count"
}

# Determine regime based on congestion score ratio
decide_regime() {
  local congest_count="$1"
  local total=$HISTORY_SIZE
  local ratio=$(( congest_count * 100 / total ))
  # Simple heuristic: if more than half of history shows congestion -> SHARED
  if (( congest_count >= ( (total*3) / 5 ) )); then
    echo "SHARED"
  else
    echo "SINGLE_OWNER"
  fi
}

while true; do
  rtt_p99=$(ping -c $PING_COUNT "$TARGET_IP" | awk -F'/' '/rtt/ {print $7}')
  [[ -z "$rtt_p99" ]] && rtt_p99=0
  ecn_ce=$(get_ecn_ce)
  retr=$(get_retrans)

  update_history "$rtt_p99" "$ecn_ce" "$retr"

  congest_count=$(compute_score)
  regime=$(decide_regime "$congest_count")
  now=$(get_time)

  if [[ "$regime" != "$last_regime" ]]; then
    (( consec_count++ ))
  else
    consec_count=0
  fi

  # Only flip if regime held consistently for M intervals and cooldown passed
  if [[ "$regime" != "$last_regime" ]] && [[ $consec_count -ge $REQUIRED_CONSEC ]]; then
    if (( now >= flip_cooldown_until )); then
      flip_cooldown_until=$(( now + COOLDOWN_SEC ))
      last_regime="$regime"
      echo "$regime" > "$REGIME_FILE"
      echo "[R-HYBRID] Flip to $regime (congest_count=$congest_count / $HISTORY_SIZE)"

      # SSM signal
      aws ssm send-command \
        --targets "Key=tag:Name,Values=$SENDER_TAG" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"/home/ec2-user/scripts/rhybrid_apply.sh $regime\"]" \
        --comment "R-Hybrid regime flip: $regime" \
        >/dev/null
    fi
  fi

  sleep "$WINDOW_SEC"
done
