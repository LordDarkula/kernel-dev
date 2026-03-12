#!/usr/bin/env bash
set -euo pipefail

# Experimental runner:
#  1) Start numa_mem_plot in background
#  2) Start hot_cold
#  3) Wait 30s
#  4) Start memory contention on NUMA node 0 using stress-ng

# -------------------------------------------------------------------
# Experiment output directory (human-readable timestamp)
# -------------------------------------------------------------------
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
EXP_DIR="experiments/numa_migration_experiment-${TIMESTAMP}"
mkdir -p "${EXP_DIR}"

CSV_OUT="${EXP_DIR}/exp1.csv"
PNG_OUT="${EXP_DIR}/exp1.png"

HOT_COLD_MEM_MB="${HOT_COLD_MEM_MB:-1024}"
HOT_COLD_NUMA_NODE="${HOT_COLD_NUMA_NODE:-1}"
HOT_COLD_TOUCH_PERCENT="${HOT_COLD_TOUCH_PERCENT:-75}"
HOT_COLD_CMD="${HOT_COLD_CMD:-./apps/hot_cold/hot_cold ${HOT_COLD_MEM_MB} ${HOT_COLD_NUMA_NODE} ${HOT_COLD_TOUCH_PERCENT}}"

WAIT_BEFORE_CONTEND="${WAIT_BEFORE_CONTEND:-120}"
WAIT_AFTER_CONTEND="${WAIT_AFTER_CONTEND:-60}"

# stress-ng parameters
STRESS_DURATION="${STRESS_DURATION:-60}"
STRESS_VM_WORKERS="${STRESS_VM_WORKERS:-4}"
STRESS_VM_BYTES="${STRESS_VM_BYTES:-4G}"
STRESS_EXTRA_ARGS="${STRESS_EXTRA_ARGS:---vm-keep --page-in}"

PLOT_DURATION=$(( WAIT_BEFORE_CONTEND + STRESS_DURATION + WAIT_AFTER_CONTEND - 1 ))

PLOT_CMD="${PLOT_CMD:-python3 -m numa_mem_plot \
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

if ! command -v python3 >/dev/null 2>&1; then
  echo "[error] python3 is not installed. Install Python and rerun the experiment."
  exit 1
fi

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

echo "[step] starting hot_cold..."
( exec ${HOT_COLD_CMD} ) >"$hc_log" 2>&1 &
hc_pid=$!
echo "[info] hot_cold pid=$hc_pid"

echo "[step] starting numa_mem_plot in background..."
( exec ${PLOT_CMD} ) >"$plot_log" 2>&1 &
plot_pid=$!
echo "[info] numa_mem_plot pid=$plot_pid"

sleep 1
if ! kill -0 "${plot_pid}" 2>/dev/null; then
  if ! wait "${plot_pid}"; then
    echo "[error] failed to start numa_mem_plot. Install `numa_mem_plot` and rerun the experiment."
    echo "[error] see ${plot_log} for details."
    exit 1
  fi
fi

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

echo "[step] leaving hot_cold and numa_mem_plot running for ${WAIT_AFTER_CONTEND}s..."
sleep "${WAIT_AFTER_CONTEND}"

echo "[done] experiment complete."
echo "       CSV: ${CSV_OUT}"
echo "       PNG: ${PNG_OUT}"
echo "       Logs: ${LOGDIR}"
