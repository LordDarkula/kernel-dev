#!/usr/bin/env bash
set -euo pipefail

# Experimental runner:
#  1) Start numa_mem_plot.py in background
#  2) Start hot_cold
#  3) Wait 30s
#  4) Start memory contention on NUMA node 0 using stress-ng
#
# Assumptions:
#  - numa_mem_plot.py is in PATH or current dir
#  - hot_cold is in PATH or current dir
#  - numactl and stress-ng are installed
#  - You have permissions to run stress-ng (may need sudo)

PLOT_CMD="${PLOT_CMD:-python3 ./numa_mem_plot.py --interval 1 --duration 120 --csv exp1.csv --out exp1.png}"
# allocs 48 GiB on Node 1 and touched 25 % of it
HOT_COLD_CMD="${HOT_COLD_CMD:-./hot_cold 49152 1 25}"
WAIT_BEFORE_CONTEND="${WAIT_BEFORE_CONTEND:-30}"

# stress-ng parameters (tune as needed)
STRESS_DURATION="${STRESS_DURATION:-60}"         # seconds
STRESS_VM_WORKERS="${STRESS_VM_WORKERS:-4}"      # number of vm workers
STRESS_VM_BYTES="${STRESS_VM_BYTES:-4G}"        # per-worker vm bytes (stress-ng syntax)
STRESS_EXTRA_ARGS="${STRESS_EXTRA_ARGS:---vm-keep --page-in}"

LOGDIR="${LOGDIR:-./exp_logs_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$LOGDIR"

plot_log="$LOGDIR/numa_mem_plot.log"
hc_log="$LOGDIR/hot_cold.log"
stress_log="$LOGDIR/stress_ng.log"

plot_pid=""
hc_pid=""
stress_pid=""

cleanup() {
  echo "[cleanup] stopping background processes..."
  [[ -n "${stress_pid}" ]] && kill "${stress_pid}" 2>/dev/null || true
  [[ -n "${hc_pid}" ]] && kill "${hc_pid}" 2>/dev/null || true
  [[ -n "${plot_pid}" ]] && kill "${plot_pid}" 2>/dev/null || true

  # Give them a moment, then force kill if needed
  sleep 1
  [[ -n "${stress_pid}" ]] && kill -9 "${stress_pid}" 2>/dev/null || true
  [[ -n "${hc_pid}" ]] && kill -9 "${hc_pid}" 2>/dev/null || true
  [[ -n "${plot_pid}" ]] && kill -9 "${plot_pid}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[info] logs: $LOGDIR"

echo "[enabling] demotion and NUMA load balancing"

sudo swapoff -a # Disable swap
echo 1 | sudo tee /sys/kernel/mm/numa/demotion_enabled # Enable page demotion
echo 6 | sudo tee /proc/sys/kernel/numa_balancing # Enable colloid

echo "[step] starting hot_cold..."
( exec ${HOT_COLD_CMD} ) >"$hc_log" 2>&1 &
hc_pid=$!
echo "[info] hot_cold pid=$hc_pid"

echo "[step] starting numa_mem_plot.py in background..."
( exec ${PLOT_CMD} ) >"$plot_log" 2>&1 &
plot_pid=$!
echo "[info] numa_mem_plot.py pid=$plot_pid"

echo "[step] waiting ${WAIT_BEFORE_CONTEND}s before introducing contention..."
sleep "${WAIT_BEFORE_CONTEND}"

echo "[step] starting stress-ng contention on NUMA node 0..."
# Bind allocations to node 0; if you also want CPU placement, add: --cpunodebind=0
# If stress-ng needs sudo on your setup, change "stress-ng" to "sudo stress-ng"
( exec numactl --cpunodebind=0 --membind=0 stress-ng \
    --vm "${STRESS_VM_WORKERS}" \
    --vm-bytes "${STRESS_VM_BYTES}" \
    --timeout "${STRESS_DURATION}s" \
    ${STRESS_EXTRA_ARGS} ) >"$stress_log" 2>&1 &
stress_pid=$!
echo "[info] stress-ng pid=$stress_pid"

echo "[step] waiting for stress-ng to finish (timeout=${STRESS_DURATION}s)..."
wait "${stress_pid}" || true
echo "[info] stress-ng done."

echo "[step] leaving hot_cold and numa_mem_plot.py running for another ${WAIT_BEFORE_CONTEND}s (optional cooldown)..."
sleep "${WAIT_BEFORE_CONTEND}"

echo "[done] experiment complete. Logs are in: $LOGDIR"
# cleanup trap will stop background processes