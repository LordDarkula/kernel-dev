#!/usr/bin/env python3
import argparse
import subprocess
import time
import re
from datetime import datetime

import matplotlib.pyplot as plt


def get_pid(proc_name: str) -> str:
    try:
        pid = subprocess.check_output(["pidof", proc_name], text=True).strip()
        # If multiple PIDs exist, take the first
        return pid.split()[0]
    except subprocess.CalledProcessError:
        raise RuntimeError(f"Process '{proc_name}' not running")


def run_numastat_p(pid: str) -> str:
    return subprocess.check_output(
        ["numastat", "-p", pid],
        text=True,
        stderr=subprocess.STDOUT,
    )


def parse_per_node_usage(numastat_output: str) -> dict[int, float]:
    """
    Parses numastat -p output and returns {node_id: used_mib}

    Example format (varies slightly by distro):

                       Node 0 Node 1
    numa_hit              123   456
    numa_miss               10    20
    local_node            100   400
    other_node             23    56
    MemUsed              1024  4096
    """

    lines = [ln.strip() for ln in numastat_output.splitlines() if ln.strip()]

    # Header line with Node IDs
    header = None
    for ln in lines:
        if re.search(r"\bNode\s+\d+\b", ln):
            header = ln
            break
    if header is None:
        raise ValueError("Could not find NUMA node header")

    node_ids = [int(x) for x in re.findall(r"\bNode\s+(\d+)\b", header)]

    # Prefer MemUsed, fallback to total of local+other
    used_vals = None
    for ln in lines:
        if ln.startswith("MemUsed"):
            nums = re.findall(r"[-+]?\d*\.?\d+", ln)
            used_vals = [float(x) for x in nums[-len(node_ids):]]
            break

    if used_vals is None:
        # Fallback: local_node + other_node
        local = other = None
        for ln in lines:
            if ln.startswith("local_node"):
                local = [float(x) for x in re.findall(r"\d+\.?\d*", ln)[-len(node_ids):]]
            if ln.startswith("other_node"):
                other = [float(x) for x in re.findall(r"\d+\.?\d*", ln)[-len(node_ids):]]
        if local and other:
            used_vals = [l + o for l, o in zip(local, other)]
        else:
            raise ValueError("Could not determine per-node memory usage")

    return {node_ids[i]: used_vals[i] for i in range(len(node_ids))}


def main():
    ap = argparse.ArgumentParser(
        description="Monitor per-NUMA memory usage of hot_cold using numastat -p"
    )
    ap.add_argument("--proc", default="hot_cold", help="Process name (default: hot_cold)")
    ap.add_argument("--interval", type=float, default=1.0, help="Sampling interval (s)")
    ap.add_argument("--duration", type=float, default=60.0, help="Total duration (s)")
    ap.add_argument("--out", default="hot_cold_numa_mem.png", help="Output plot file")
    ap.add_argument("--csv", default=None, help="Optional CSV output")
    args = ap.parse_args()

    pid = get_pid(args.proc)
    print(f"Monitoring PID {pid} ({args.proc})")

    start = time.time()
    ts = []
    series = {}  # node_id -> list of used_mib

    csv_f = None
    if args.csv:
        csv_f = open(args.csv, "w", encoding="utf-8")
        csv_f.write("t_seconds,iso_time,node,used_mib\n")

    try:
        while True:
            t = time.time() - start
            if t > args.duration:
                break

            out = run_numastat_p(pid)
            usage = parse_per_node_usage(out)

            ts.append(t)
            for node_id, used in usage.items():
                series.setdefault(node_id, []).append(used)
                if args.csv:
                    csv_f.write(
                        f"{t:.3f},{datetime.now().isoformat(timespec='seconds')},{node_id},{used}\n"
                    )

            # Keep series aligned
            for node_id in series:
                if len(series[node_id]) < len(ts):
                    series[node_id].append(float("nan"))

            time.sleep(args.interval)

    finally:
        if csv_f:
            csv_f.close()

    # Plot
    plt.figure()
    for node_id in sorted(series):
        plt.plot(ts, series[node_id], label=f"Node {node_id}")
    plt.xlabel("Time (s)")
    plt.ylabel("Memory Used (MiB)")
    plt.title(f"NUMA memory usage of {args.proc} (pid {pid})")
    plt.legend()
    plt.tight_layout()
    plt.savefig(args.out, dpi=200)
    print(f"Wrote plot to {args.out}")
    if args.csv:
        print(f"Wrote CSV to {args.csv}")


if __name__ == "__main__":
    main()
