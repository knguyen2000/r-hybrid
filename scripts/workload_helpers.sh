run_workload() {
  local workload="$1"
  local flows="$2"
  local server_ip="$3"
  local out_dir="$4"

  case "$workload" in
    iperf)
      for ((i=1; i<=flows; i++)); do
        nohup iperf3 -c "$server_ip" -t 90 -i 1 --logfile "${out_dir}/iperf_${i}.log" &
      done
      wait
      ;;
    http)
      for ((i=1; i<=flows; i++)); do
        curl -o /dev/null -s -w "%{time_starttransfer}\n" "http://${server_ip}/big.bin" >> "${out_dir}/http_ttfb.txt"
      done
      ;;
    hls)
      for ((i=1; i<=flows; i++)); do
        for seg in $(seq 1 20); do
          curl -o /dev/null -s -w "%{time_total}\n" "http://${server_ip}/seg${seg}.ts" >> "${out_dir}/hls_latency.txt"
        done
      done
      ;;
  esac
}
