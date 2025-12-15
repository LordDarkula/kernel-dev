#!/usr/bin/env python3
import argparse
import subprocess
import time
import re
from datetime import datetime

import matplotlib.pyplot as plt


def run_numastat_m() -> str:
    # `numastat -m` prints a table; we capture stdout as text
    return subprocess.check_output(["numastat", "-m"], text=True, stderr=subprocess.STDOUT)


def parse_used_per_node(numastat_output: str) -> dict[int, float]:
    """
    Returns {node_id: used_mib} parsed from numastat -m output.

    Prefers MemUsed. Falls back to Used.
    """
    lines = [ln.strip() for ln in numastat_output.splitlines() if ln.strip()]
    if not lines:
        raise ValueError("Empty numastat output")

    # Find header line containing "Node 0", "Node 1", etc.
    header_idx = None
    node_ids = []
    for i, ln in enumerate(lines):
        if re.search(r"\bNode\s+\d+\b", ln):
            header_idx = i
            node_ids = [int(x) for x in re.findall(r"\bNode\s+(\d+)\b", ln)]
            break

    if header_idx is None or not node_ids:
        raise ValueError("Could not find NUMA node header in numastat output")

    def find_row(label: str) -> list[float] | None:
        for ln in lines[header_idx + 1 :]:
            if ln.startswith(label):
                # Extract all numeric columns on the line
                nums = re.findall(r"[-+]?\d*\.?\d+", ln)
                # First number might be part of label sometimes; best effort:
                # Keep the last N numbers where N == number of nodes.
                if len(nums) >= len(node_ids):
                    vals = [float(x) for x in nums[-len(node_ids):]]
                    return vals
        return None

    vals = find_row("MemUsed")
    if vals is None:
        vals = find_row("Used")
    if vals is None:
        raise ValueError("Could not find MemUsed or Used row in numastat -m output")

    return {node_id: vals[j] for j, node_id in enumerate(node_ids)}


def main():
    ap = argparse.ArgumentParser(description="Monitor numastat -m MemUsed per NUMA node and plot over time.")
    ap.add_argument("--interval", type=float, default=1.0, help="Sampling interval in seconds (default: 1.0)")
    ap.add_argument("--duration", type=float, default=60.0, help="Total duration in seconds (default: 60)")
    ap.add_argument("--out", default="numa_mem_used.png", help="Output plot filename (default: numa_mem_used.png)")
    ap.add_argument("--csv", default=None, help="Optional: write samples to CSV file")
    args = ap.parse_args()

    start = time.time()
    ts = []
    series = {}  # node_id -> list of used_mib

    csv_f = None
    if args.csv:
        csv_f = open(args.csv, "w", encoding="utf-8")
        csv_f.write("t_seconds,iso_time,node,used_mib\n")

    try:
        while True:
            now = time.time()
            t = now - start
            if t > args.duration:
                break

            out = run_numastat_m()
            used = parse_used_per_node(out)

            ts.append(t)
            for node_id, used_mib in used.items():
                series.setdefault(node_id, []).append(used_mib)
                if csv_f:
                    csv_f.write(f"{t:.3f},{datetime.now().isoformat(timespec='seconds')},{node_id},{used_mib}\n")

            # Ensure all node series align if nodes appear later (rare)
            for node_id in series:
                if len(series[node_id]) < len(ts):
                    series[node_id].append(float("nan"))

            time.sleep(args.interval)

    finally:
        if csv_f:
            csv_f.close()

    # Plot
    plt.figure()
    for node_id in sorted(series.keys()):
        plt.plot(ts, series[node_id], label=f"Node {node_id}")
    plt.xlabel("Time (s)")
    plt.ylabel("MemUsed (MiB)")
    plt.title("NUMA node memory used over time (numastat -m)")
    plt.legend()
    plt.tight_layout()
    plt.savefig(args.out, dpi=200)
    print(f"Wrote plot to {args.out}")
    if args.csv:
        print(f"Wrote samples to {args.csv}")


if __name__ == "__main__":
    main()
