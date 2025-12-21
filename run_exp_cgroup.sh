#!/usr/bin/env bash
set -euo pipefail

# Experimental runner:
#  1) Start numa_mem_plot.py in background
#  2) Start hot_cold inside cgroup hot-cold-cg
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

# allocs 50 GiB on Node 1 and touches 75%
HOT_COLD_CMD="${HOT_COLD_CMD:-./apps/hot_cold/hot_cold 51200 1 75}"
WAIT_BEFORE_CONTEND="${WAIT_BEFORE_CONTEND:-120}"
WAIT_AFTER_CONTEND="${WAIT_AFTER_CONTEND:-60}"

# stress-ng parameters
STRESS_DURATION="${STRESS_DURATION:-60}"
STRESS_VM_WORKERS="${STRESS_VM_WORKERS:-4}"
STRESS_VM_BYTES="${STRESS_VM_BYTES:-4G}"
STRESS_EXTRA_ARGS="${STRESS_EXTRA_ARGS:---vm-keep --page-in}"

PLOT_DURATION=$(( WAIT_BEFORE_CONTEND + STRESS_DURATION + WAIT_AFTER_CONTEND - 10 ))

PLOT_CMD="${PLOT_CMD:-python3 ./numa_mem_plot.py \
  --interval 1 \
  --duration ${PLOT_DURATION} \
  --csv ${CSV_OUT} \
  --out ${PNG_OUT}}"

# -------------------------------------------------------------------
# Cgroup setup (supports cgroup v2; will also work on v1 if cgexec exists)
# -------------------------------------------------------------------
CGROUP_NAME="hot-cold-cg"
CGROUPV2_MNT="/sys/fs/cgroup"
CGROUP_PATH="${CGROUPV2_MNT}/${CGROUP_NAME}"

setup_cgroup() {
  if [[ -f "${CGROUPV2_MNT}/cgroup.controllers" ]]; then
    # cgroup v2
    echo "[info] using cgroup v2 at ${CGROUPV2_MNT}"
    sudo mkdir -p "${CGROUP_PATH}"

    # Enable controllers on the parent so subtree can use them (best-effort).
    # (Not strictly required just to place a process in a cgroup.)
    if [[ -w "${CGROUPV2_MNT}/cgroup.subtree_control" ]]; then
      sudo bash -c "echo '+memory +cpu +cpuset' > '${CGROUPV2_MNT}/cgroup.subtree_control' 2>/dev/null || true"
    fi
  else
    # cgroup v1 fallback requires cgexec
    if ! command -v cgexec >/dev/null 2>&1; then
      echo "[warn] cgroup v1 detected but cgexec not found; hot_cold will run without cgroup"
      return 0
    fi
    echo "[info] using cgroup v1 via cgexec"
  fi
}

run_in_cgroup_bg() {
  # Runs HOT_COLD_CMD in the cgroup in the background and echoes the PID.
  if [[ -f "${CGROUPV2_MNT}/cgroup.controllers" ]]; then
    # cgroup v2: start process, then move it into the cgroup
    # Use setsid so the process has its own session (cleaner for experiment scripts)
    setsid bash -lc "exec ${HOT_COLD_CMD}" >"$hc_log" 2>&1 &
    local pid=$!
    # Move it into cgroup
    echo "$pid" | sudo tee "${CGROUP_PATH}/cgroup.procs" >/dev/null
    echo "$pid"
  else
    # cgroup v1: cgexec launches directly in the cgroup (if installed)
    # NOTE: controller name here is "memory"; adjust if you want others.
    cgexec -g "memory:${CGROUP_NAME}" bash -lc "exec ${HOT_COLD_CMD}" >"$hc_log" 2>&1 &
    echo $!
  fi
}

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

echo "[info] experiment dir: ${EXP_DIR}"
echo "[info] logs: ${LOGDIR}"

setup_cgroup

echo "[step] starting hot_cold in cgroup '${CGROUP_NAME}'..."
hc_pid="$(run_in_cgroup_bg)"
echo "[info] hot_cold pid=$hc_pid"

echo "[step] starting numa_mem_plot.py in background..."
( exec ${PLOT_CMD} ) >"$plot_log" 2>&1 &
plot_pid=$!
echo "[info] numa_mem_plot.py pid=$plot_pid"

echo "[step] waiting ${WAIT_BEFORE_CONTEND}s before introducing contention..."
sleep "${WAIT_BEFORE_CONTEND}"

echo "[step] starting stress-ng contention on NUMA node 0..."
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