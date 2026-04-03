#!/usr/bin/env bash
set -euo pipefail

# Experimental runner:
#  1) Start numa_mem_plot in background
#  2) Start hot_cold
#  3) Let the baseline run without injected contention

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <kernel_mode>" >&2
  echo "  kernel_mode must be one of: tpp, colloid" >&2
  exit 1
fi

readonly KERNEL_MODE="$1"

if [[ "${KERNEL_MODE}" != "tpp" && "${KERNEL_MODE}" != "colloid" ]]; then
  echo "[error] invalid kernel_mode '${KERNEL_MODE}'. Expected 'tpp' or 'colloid'." >&2
  exit 1
fi

# -------------------------------------------------------------------
# Experiment output directory (human-readable timestamp)
# -------------------------------------------------------------------
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
EXP_DIR="experiments/numa_baseline_experiment-${TIMESTAMP}"
mkdir -p "${EXP_DIR}"

CSV_OUT="${EXP_DIR}/memory_usage.csv"
PNG_OUT="${EXP_DIR}/memory_usage.png"
PARAMS_OUT="${EXP_DIR}/experimental_params.yaml"

HOT_COLD_BIN="${HOT_COLD_BIN:-./apps/hot_cold/hot_cold}"
HOT_COLD_MEM_MB="${HOT_COLD_MEM_MB:-16384}"
SLOW_NUMA_NODE="${SLOW_NUMA_NODE:-1}"
HOT_COLD_TOUCH_PERCENT="${HOT_COLD_TOUCH_PERCENT:-25}"
HOT_COLD_CMD="${HOT_COLD_CMD:-${HOT_COLD_BIN} ${HOT_COLD_MEM_MB} ${SLOW_NUMA_NODE} ${HOT_COLD_TOUCH_PERCENT}}"

BASELINE_DURATION="${BASELINE_DURATION:-60}"

PLOT_DURATION=$(( BASELINE_DURATION - 1 ))

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
plot_pid=""
hc_pid=""

yaml_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

write_params_yaml() {
  cat >"${PARAMS_OUT}" <<EOF
timestamp: $(yaml_quote "${TIMESTAMP}")
experiment_dir: $(yaml_quote "${EXP_DIR}")
csv_out: $(yaml_quote "${CSV_OUT}")
png_out: $(yaml_quote "${PNG_OUT}")
kernel_mode: $(yaml_quote "${KERNEL_MODE}")
logdir: $(yaml_quote "${LOGDIR}")
plot_log: $(yaml_quote "${plot_log}")
hot_cold_log: $(yaml_quote "${hc_log}")
hot_cold_mem_mb: ${HOT_COLD_MEM_MB}
slow_numa_node: ${SLOW_NUMA_NODE}
hot_cold_touch_percent: ${HOT_COLD_TOUCH_PERCENT}
hot_cold_cmd: $(yaml_quote "${HOT_COLD_CMD}")
baseline_duration: ${BASELINE_DURATION}
plot_duration: ${PLOT_DURATION}
plot_cmd: $(yaml_quote "${PLOT_CMD}")
EOF
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "[error] python3 is not installed. Install Python and rerun the experiment."
  exit 1
fi

if [[ ! -x "${HOT_COLD_BIN}" ]]; then
  echo "[error] hot_cold binary not found or not executable at '${HOT_COLD_BIN}'." >&2
  echo "[error] build it first, for example: make -C apps/hot_cold" >&2
  exit 1
fi

cleanup() {
  echo "[cleanup] stopping background processes..."
  [[ -n "${hc_pid}" ]] && kill "${hc_pid}" 2>/dev/null || true
  [[ -n "${plot_pid}" ]] && kill "${plot_pid}" 2>/dev/null || true

  sleep 1
  [[ -n "${hc_pid}" ]] && kill -9 "${hc_pid}" 2>/dev/null || true
  [[ -n "${plot_pid}" ]] && kill -9 "${plot_pid}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[info] experiment dir: ${EXP_DIR}"
echo "[info] logs: ${LOGDIR}"
write_params_yaml
echo "[info] params: ${PARAMS_OUT}"

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

echo "[step] leaving hot_cold and numa_mem_plot running for ${BASELINE_DURATION}s..."
sleep "${BASELINE_DURATION}"

echo "[done] experiment complete."
echo "       CSV: ${CSV_OUT}"
echo "       PNG: ${PNG_OUT}"
echo "       Params: ${PARAMS_OUT}"
echo "       Logs: ${LOGDIR}"
