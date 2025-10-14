#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  # FIX: Now takes IPs for both servers as arguments.
  echo "Usage: $0 <SERVER_A_PRIVATE_IP> <SERVER_B_PRIVATE_IP>"
  exit 1
fi

SERVER_A_IP="$1"
SERVER_B_IP="$2"
# This variable will be updated for each test run.
SERVER_IP=""

CSV="/var/log/net-experiments.csv"
# ... (rest of the variables are unchanged) ...

# ... (helper functions are unchanged) ...

run_bundle() {
  local EXP="$1" TOPO="$2" CC="$3" MTU="$4" IMP="$5" LOAD="$6" NOTES="$7"

  # FIX: Select the correct server IP based on the topology for this test run.
  if [[ "$TOPO" == "T1" ]]; then
    SERVER_IP="$SERVER_A_IP" # T1 = intra-AZ
  elif [[ "$TOPO" == "T2" ]]; then
    SERVER_IP="$SERVER_B_IP" # T2 = cross-AZ
  else
    # For IGW tests, we'd use a public IP, but for now, default to intra-AZ.
    SERVER_IP="$SERVER_A_IP"
  fi
  echo "[*] $EXP: topo=$TOPO (target server: $SERVER_IP) cc=$CC mtu=$MTU impair=$IMP load=$LOAD"

  # FIX: Only set CC manually if it's NOT a hybrid test.
  if [[ "$CC" != "hybrid" ]]; then
    cc_set "$CC"
  else
    echo "Hybrid mode detected. CC is managed by the receiver agent."
  fi
  
  # ... (impairment and test execution logic is unchanged) ...

  # FIX: Run application-layer tests for the H4 experiment.
  if [[ "$EXP" == "H4" ]]; then
    # Redefine URLs with the correct server IP for this run
    HTTP_URL_BIG="http://${SERVER_IP}/big.bin"
    HLS_URL_PREFIX="http://${SERVER_IP}/hls/seg"
    echo "Running application layer tests for H4..."
    app_progressive
    app_hls_loop
  else
    : > /tmp/app_progressive.txt || true
    : > /tmp/app_hls_avg || true
  fi

  record "$EXP" "$TOPO" "$CC" "$MTU" "$IMP" "$LOAD" "$NOTES"
  impair_clear
}

# Baselines (T1 tests will target server_a)
run_bundle E1   T1 cubic  1500 none   none "baseline same-AZ private, CUBIC"
run_bundle E2   T1 bbr    1500 none   none "baseline BBR"
run_bundle E3   T1 dctcp  1500 none   none "baseline DCTCP"

# Hybrid experiments
run_bundle H1   T1 hybrid 1500 none   none "R-Hybrid intra-AZ"
run_bundle H2   T2 hybrid 1500 none   none "R-Hybrid cross-AZ" # This now correctly targets server_b
run_bundle H3   T1 hybrid 1500 none   none "R-Hybrid IGW (simulated intra-AZ)"
run_bundle H4   T1 hybrid 1500 d50l1p none "R-Hybrid impairments"

echo "Done. CSV at: $CSV"

if [[ -n "${RESULT_S3_URI:-}" ]]; then
  TS=$(date +%Y%m%d-%H%M%S)
  /usr/bin/aws s3 cp "$CSV" "${RESULT_S3_URI%/}/net-experiments-$TS.csv"
  /usr/bin/aws s3 cp "$SWITCH_LOG" "${RESULT_S3_URI%/}/cc_switch_events.csv"
fi
