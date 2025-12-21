#!/usr/bin/env bash
set -euo pipefail

# Experimental runner:
#  1) Start numa_mem_plot.py in background
#  2) Start hot_cold inside cgroup hot-cold-cg (cgroup v2)
#  3) Wait WAIT_BEFORE_CONTEND
#  4) Start memory contention on NUMA node 0 using stress-ng

# -------------------------------------------------------------------
# Experiment output directory (human-readable timestamp)
# -------------------------------------------------------------------
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
EXP_DIR="experiments/exp1-${TIMESTAMP}"
mkdir -p "${EXP_DIR}"

CSV_OUT="${EXP_DIR}/exp1.csv"
PNG_OUT="${EXP_DIR}/exp1.png"

# -------------------------------------------------------------------
# Workload config
# -------------------------------------------------------------------
# allocs 50 GiB on Node 1 and touches 75%
HOT_COLD_CMD="${HOT_COLD_CMD:-./apps/hot_cold/hot_cold 51200 1 75}"
WAIT_BEFORE_CONTEND="${WAIT_BEFORE_CONTEND:-120}"
WAIT_AFTER_CONTEND="${WAIT_AFTER_CONTEND:-60}"

# stress-ng parameters
STRESS_DURATION="${STRESS_DURATION:-60}"
STRESS_VM_WORKERS="${STRESS_VM_WORKERS:-4}"
STRESS_VM_BYTES="${STRESS_VM_BYTES:-4G}"
STRESS_EXTRA_ARGS="${STRESS_EXTRA_ARGS:---vm-keep --page-in}"

# Plot duration = total experiment time minus a small slack
PLOT_DURATION=$(( WAIT_BEFORE_CONTEND + STRESS_DURATION + WAIT_AFTER_CONTEND - 10 ))
if (( PLOT_DURATION < 1 )); then
  PLOT_DURATION=1
fi

PLOT_CMD="${PLOT_CMD:-python3 ./numa_mem_plot.py \
  --interval 1 \
  --duration ${PLOT_DURATION} \
  --csv ${CSV_OUT} \
  --out ${PNG_OUT}}"

# -------------------------------------------------------------------
# Logs (kept separate from experiment artifacts)
# -------------------------------------------------------------------
LOGDIR="${LOGDIR:-./exp_logs_${TIMESTAMP}}"
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

  sleep 1
  [[ -n "${stress_pid}" ]] && kill -9 "${stress_pid}" 2>/dev/null || true
  [[ -n "${hc_pid}" ]] && kill -9 "${hc_pid}" 2>/dev/null || true
  [[ -n "${plot_pid}" ]] && kill -9 "${plot_pid}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# -------------------------------------------------------------------
# Cgroup v2 setup + launch helper
# -------------------------------------------------------------------
CGROUP_NAME="hot-cold-cg"
CGROOT="/sys/fs/cgroup"
CGPATH="${CGROOT}/${CGROUP_NAME}"

ensure_cgroup_v2() {
  if [[ ! -f "${CGROOT}/cgroup.controllers" ]]; then
    echo "[fatal] cgroup v2 not mounted at ${CGROOT} (no cgroup.controllers)."
    echo "        If your system uses cgroup v1, you must use cgexec instead."
    exit 1
  fi
  sudo mkdir -p "${CGPATH}"

  # Best-effort: enable controllers on the root so children can use them.
  # Not strictly required just to place a process in a cgroup.
  if [[ -w "${CGROOT}/cgroup.subtree_control" ]]; then
    sudo bash -c "echo '+memory +cpu +cpuset' > '${CGROOT}/cgroup.subtree_control' 2>/dev/null || true"
  fi
}

start_hot_cold_in_cgroup() {
  echo "[step] starting hot_cold (will move into cgroup '${CGROUP_NAME}')..."

  # Start as current user (same behavior as before); then move PID into cgroup.
  bash -c "exec ${HOT_COLD_CMD}" >"$hc_log" 2>&1 &
  local pid=$!

  # Give it a moment to either initialize or crash.
  sleep 0.2

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[fatal] hot_cold exited immediately (pid=$pid). Last 80 log lines:"
    tail -n 80 "$hc_log" || true
    exit 1
  fi

  if ! echo "$pid" | sudo tee "${CGPATH}/cgroup.procs" >/dev/null; then
    echo "[fatal] failed to move hot_cold pid=$pid into ${CGPATH}."
    echo "        Last 80 log lines:"
    tail -n 80 "$hc_log" || true
    exit 1
  fi

  # Verify placement (best-effort)
  if ! sudo grep -qx "$pid" "${CGPATH}/cgroup.procs" 2>/dev/null; then
    echo "[warn] hot_cold pid=$pid not visible in ${CGPATH}/cgroup.procs (unexpected)."
  fi

  echo "$pid"
}

# -------------------------------------------------------------------
# Run experiment
# -------------------------------------------------------------------
echo "[info] experiment dir: ${EXP_DIR}"
echo "[info] logs: ${LOGDIR}"
echo "[info] cgroup: ${CGPATH}"

ensure_cgroup_v2

echo "[step] starting hot_cold in cgroup..."
hc_pid="$(start_hot_cold_in_cgroup)"
echo "[info] hot_cold pid=$hc_pid"

echo "[step] starting numa_mem_plot.py in background..."
( exec ${PLOT_CMD} ) >"$plot_log" 2>&1 &
plot_pid=$!
echo "[info] numa_mem_plot.py pid=$plot_pid"

echo "[step] waiting ${WAIT_BEFORE_CONTEND}s before introducing contention..."
sleep "${WAIT_BEFORE_CONTEND}"

echo "[step] starting stress-ng contention on NUMA node 0..."
# NOTE: This uses the vm stressor (DRAM traffic). If you intentionally want STREAM, change it.
( exec numactl --cpunodebind=0 --membind=0 stress-ng \
    --stream "${STRESS_VM_WORKERS}" \
    --stream-l3-size "${STRESS_VM_BYTES}" \
    --timeout "${STRESS_DURATION}s" \
    ${STRESS_EXTRA_ARGS} ) >"$stress_log" 2>&1 &
stress_pid=$!
echo "[info] stress-ng pid=$stress_pid"

echo "[step] waiting for stress-ng to finish (timeout=${STRESS_DURATION}s)..."
wait "${stress_pid}" || true
echo "[info] stress-ng done."

echo "[step] leaving hot_cold and numa_mem_plot.py running for ${WAIT_AFTER_CONTEND}s..."
sleep "${WAIT_AFTER_CONTEND}"

echo "[done] experiment complete."
echo "       CSV: ${CSV_OUT}"
echo "       PNG: ${PNG_OUT}"
echo "       Logs: ${LOGDIR}"
echo "       hot_cold cgroup procs: (head)"
sudo head -n 20 "${CGPATH}/cgroup.procs" 2>/dev/null || true
