#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="$1"
RESULTS_DIR="/home/ec2-user/results"
mkdir -p "$RESULTS_DIR"

PATHS=("single-owner" "shared-crossaz" "shared-igw" "mixed")
IMPAIRMENTS=("none" "delay_20ms" "loss_1pct" "delay_jitter" "dynamic_switch")
FLOWS=(1 4 8)
CC_MODES=("cubic" "dctcp" "bbr" "hybrid")
WORKLOADS=("iperf" "http" "hls")

source "$(dirname "$0")/impair_helpers.sh"
source "$(dirname "$0")/workload_helpers.sh"

EXP_ID=1
for path in "${PATHS[@]}"; do
  for impairment in "${IMPAIRMENTS[@]}"; do
    for flows in "${FLOWS[@]}"; do
      for cc_mode in "${CC_MODES[@]}"; do
        for workload in "${WORKLOADS[@]}"; do
          
          exp_dir="${RESULTS_DIR}/exp_${EXP_ID}_${path}_${impairment}_${flows}f_${cc_mode}_${workload}"
          mkdir -p "$exp_dir"
          echo "$(date) $path $impairment $flows $cc_mode $workload" > "${exp_dir}/meta.txt"

          apply_impairment "$impairment"
          set_cc_mode "$cc_mode"
          run_workload "$workload" "$flows" "$SERVER_IP" "$exp_dir"

          if [[ "$cc_mode" == "hybrid" ]]; then
            cp /var/log/regime_detection.log "${exp_dir}/regime_detection.log" || true
          fi

          sudo tc qdisc del dev ens5 root || true
          ((EXP_ID++))
        done
      done
    done
  done
done
