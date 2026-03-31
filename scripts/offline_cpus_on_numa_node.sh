#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <numa-node>" >&2
  exit 1
fi

if ! [[ "$1" =~ ^[0-9]+$ ]]; then
  echo "Error: NUMA node must be a non-negative integer, got '$1'." >&2
  exit 1
fi

readonly target_numa_node="$1"
readonly numa_node_count=$(lscpu | awk -F: '/NUMA node\(s\)/ {gsub(/ /, "", $2); print $2}')

if [[ -z "$numa_node_count" ]]; then
  echo "Error: failed to determine the number of NUMA nodes on this system." >&2
  exit 1
fi

if (( numa_node_count == 1 )); then
  echo "Warning: this system has only one NUMA node. Offlining its CPUs may make the system unusable." >&2
fi

if (( target_numa_node >= numa_node_count )); then
  echo "Error: NUMA node $target_numa_node does not exist on this system. Valid NUMA nodes are 0 through $((numa_node_count - 1))." >&2
  exit 1
fi

echo "Downloading dependencies ..."

sudo apt-get update -y
sudo apt-get install -y msr-tools pcm
sudo modprobe msr

# Get all CPUs on the NUMA that'll emulate slow CXL mem.
readonly cpus_to_offline=$(lscpu --parse=cpu,node | grep ",$target_numa_node$" | cut -d , -f 1)

if [[ -z "$cpus_to_offline" ]]; then
  echo "Error: no CPUs were found for NUMA node $target_numa_node." >&2
  exit 1
fi

readonly uncore_freq_reg="0x620"
readonly low_uncore_freq="0x707"
# Store the original uncore freq in a file so that we can restore its old value later.
sudo rdmsr --processor $(echo $cpus_to_offline | cut -d ' ' -f 1) $uncore_freq_reg > old_uncore_freq
# Lower the uncore freq for that NUMA node to mimic increased memory access latency.
sudo wrmsr --processor $(echo $cpus_to_offline | cut -d ' ' -f 1) $uncore_freq_reg $low_uncore_freq

echo "About to sleep"

# Give time to the new freq to kick in.
sleep 3

# Safety check to ensure that the new freq has been applied.
readonly measured_uncore_freq=$(sudo pcm-power --interval 1 --samples 1 2>&1 | \
  grep -m 3 "S$target_numa_node; Uncore Freq:" | \
  cut -d ' ' -f 4,5 | \
  tr -d ';' | \
  tr -d ' ')
for sample in $measured_uncore_freq; do
	if [[ "$sample" != "0.70Ghz" ]]; then
    echo "Fatal error: expected uncore frequency for NUMA node $target_numa_node to be 0.70Ghz, got $sample"
    exit 1
  fi
done

# Now, offline all the CPUs in the emulated NUMA node.
skipped_cpus=()
offlined_cpus=()

for id in $cpus_to_offline; do
  cpu_online_path="/sys/devices/system/cpu/cpu$id/online"

  if [[ ! -e "$cpu_online_path" ]]; then
    echo "skipping cpu$id on NUMA $target_numa_node: no online control file (likely not hotpluggable)"
    skipped_cpus+=("$id")
    continue
  fi

  if echo 0 | sudo tee "$cpu_online_path" >/dev/null; then
    echo "offlined cpu$id on NUMA $target_numa_node"
    offlined_cpus+=("$id")
  else
    echo "skipping cpu$id on NUMA $target_numa_node: kernel refused to offline it" >&2
    skipped_cpus+=("$id")
  fi
done

if (( ${#offlined_cpus[@]} == 0 )); then
  echo "Warning: no CPUs were offlined on NUMA $target_numa_node." >&2
fi

if (( ${#skipped_cpus[@]} > 0 )); then
  echo "Skipped CPUs on NUMA $target_numa_node: ${skipped_cpus[*]}" >&2
fi
