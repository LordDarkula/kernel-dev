#!/usr/bin/env python3
import argparse
import subprocess
import time
import re
import os
from datetime import datetime

import matplotlib.pyplot as plt


def get_pid(proc_name: str) -> str | None:
    """Return first PID for proc_name, or None if not running."""
    try:
        out = subprocess.check_output(["pidof", proc_name], text=True).strip()
        if not out:
            return None
        return out.split()[0]
    except subprocess.CalledProcessError:
        return None


def pid_is_alive(pid: str) -> bool:
    return os.path.exists(f"/proc/{pid}")


def run_numastat_p(pid: str) -> str:
    return subprocess.check_output(
        ["numastat", "-p", pid],
        text=True,
        stderr=subprocess.STDOUT,
    )


def parse_private_mb_per_node(numastat_output: str) -> dict[int, float]:
    """
    Parses output like:

    Per-node process memory usage (in MBs) for PID ...
                               Node 0          Node 1           Total
                      --------------- --------------- ---------------
    Huge                         0.00            0.00            0.00
    ...
    Private                  26934.04            1.63        26935.68

    Returns {0: 26934.04, 1: 1.63} in MB.
    """
    lines = [ln.rstrip() for ln in numastat_output.splitlines() if ln.strip()]

    # Find header with Node IDs
    header_line = None
    for ln in lines:
        if re.search(r"\bNode\s+\d+\b", ln):
            header_line = ln
            break
    if header_line is None:
        raise ValueError("Could not find Node header line")

    node_ids = [int(x) for x in re.findall(r"\bNode\s+(\d+)\b", header_line)]
    if not node_ids:
        raise ValueError("No node IDs found in header")

    # Find the 'Private' row
    private_line = None
    for ln in lines:
        if ln.lstrip().startswith("Private"):
            private_line = ln
            break
    if private_line is None:
        raise ValueError("Could not find 'Private' row")

    # Extract all floats on the line. Last value is Total; preceding are per-node.
    nums = re.findall(r"[-+]?\d*\.?\d+", private_line)
    if len(nums) < len(node_ids):
        raise ValueError(f"Not enough numeric columns in Private row: {private_line}")

    # The line includes per-node columns + Total. Take the first N per-node values.
    vals = [float(x) for x in nums[: len(node_ids)]]
    return {node_ids[i]: vals[i] for i in range(len(node_ids))}


def main():
    ap = argparse.ArgumentParser(description="Track per-node Private memory for hot_cold via numastat -p")
    ap.add_argument("--proc", default="hot_cold", help="Process name (default: hot_cold)")
    ap.add_argument("--interval", type=float, default=1.0, help="Sampling interval seconds (default: 1)")
    ap.add_argument("--duration", type=float, default=60.0, help="Total duration seconds (default: 60)")
    ap.add_argument("--out", default="hot_cold_private_per_node.png", help="Output plot filename")
    ap.add_argument("--csv", default=None, help="Optional CSV output filename")
    args = ap.parse_args()

    start = time.time()
    ts: list[float] = []
    series: dict[int, list[float]] = {}

    csv_f = None
    if args.csv:
        csv_f = open(args.csv, "w", encoding="utf-8")
        csv_f.write("t_seconds,iso_time,node,private_mb\n")

    # Lock onto the first PID we observe; do NOT follow restarts.
    locked_pid = get_pid(args.proc)
    if locked_pid is None:
        print(f"[warn] Process '{args.proc}' not running at start. Will wait up to {args.duration}s for it to appear.")
    else:
        print(f"Monitoring {args.proc} (PID {locked_pid}) using numastat -p, tracking Private (MB)")

    stopped_reason = None
    oom_terminated = False

    try:
        while True:
            t = time.time() - start
            if t > args.duration:
                break

            # If we don't yet have a PID, wait for process to appear.
            if locked_pid is None:
                locked_pid = get_pid(args.proc)
                if locked_pid is None:
                    time.sleep(args.interval)
                    continue
                print(f"[info] Found {args.proc} (PID {locked_pid}). Starting sampling.")

            # If locked PID is gone, stop recording (treat as OOM for visualization purposes).
            if not pid_is_alive(locked_pid):
                stopped_reason = f"process '{args.proc}' (PID {locked_pid}) exited (assume OOM)"
                oom_terminated = True
                break

            try:
                out = run_numastat_p(locked_pid)
            except subprocess.CalledProcessError as e:
                # If numastat can't read numa_maps anymore, treat as process end.
                stopped_reason = f"numastat failed for PID {locked_pid} (assume OOM): {e.output.strip()[:200]}"
                oom_terminated = True
                break
            except FileNotFoundError:
                raise RuntimeError("numastat not found in PATH")

            try:
                priv = parse_private_mb_per_node(out)
            except Exception as e:
                # Stop gracefully and still plot what we have.
                stopped_reason = f"failed to parse numastat output: {e}"
                break

            ts.append(t)
            for node_id, mb in priv.items():
                series.setdefault(node_id, []).append(mb)
                if csv_f:
                    csv_f.write(
                        f"{t:.3f},{datetime.now().isoformat(timespec='seconds')},{node_id},{mb}\n"
                    )

            # Keep lists aligned (in case a node appears later)
            for node_id in series:
                if len(series[node_id]) < len(ts):
                    series[node_id].append(float("nan"))

            time.sleep(args.interval)

    finally:
        if csv_f:
            csv_f.close()

    if stopped_reason:
        print(f"[info] stopping early: {stopped_reason}")

    # Plot: lines stop where sampling stopped; add an 'X' at last point if OOM.
    plt.figure()
    ax = plt.gca()

    for node_id in sorted(series.keys()):
        y = series[node_id]
        x = ts

        # Plot line
        (line,) = ax.plot(x, y, label=f"Node {node_id}")

        # If OOM occurred, mark final sample with X and do not extend line (sampling already stopped)
        if oom_terminated and len(x) > 0 and len(y) > 0:
            ax.plot(
                x[-1],
                y[-1],
                marker="x",
                markersize=10,
                markeredgewidth=2,
                linestyle="None",
                color=line.get_color(),
            )

    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Memory Used (MB)")
    ax.legend()
    plt.tight_layout()
    plt.savefig(args.out, dpi=200)
    print(f"Wrote plot to {args.out}")
    if args.csv:
        print(f"Wrote CSV to {args.csv}")


if __name__ == "__main__":
    main()
