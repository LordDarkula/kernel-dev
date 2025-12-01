#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

sudo apt-get update -y
sudo apt-get install -y msr-tools pcm
sudo modprobe msr

# Get all CPUs on the NUMA that'll emulate slow CXL mem.
readonly max_numa_node=$(lscpu | grep -i "NUMA node(s)" | awk  '{print $3 - 1}')
readonly cpus_to_offline=$(lscpu --parse=cpu,node | grep ,$max_numa_node$ | cut -d , -f 1)

readonly uncore_freq_reg="0x620"
readonly low_uncore_freq="0x707"
# Store the original uncore freq in a file so that we can restore its old value later.
sudo rdmsr --processor $(echo $cpus_to_offline | cut -d ' ' -f 1) $uncore_freq_reg > old_uncore_freq
# Lower the uncore freq for that NUMA node to mimic increased memory access latency.
sudo wrmsr --processor $(echo $cpus_to_offline | cut -d ' ' -f 1) $uncore_freq_reg $low_uncore_freq

# Give time to the new freq to kick in.
sleep 3

# Safety check to ensure that the new freq has been applied.
readonly measured_uncore_freq=$(sudo pcm-power 2>&1 | \
  grep -m 3 "S$max_numa_node; Uncore Freq:" | \
  cut -d ' ' -f 4,5 | \
  tr -d ';' | \
  tr -d ' ')
for sample in $measured_uncore_freq; do
	if [[ "$sample" != "0.70Ghz" ]]; then
    echo "Fatal error: expected uncore frequency for NUMA node $max_numa_node to be 0.70Ghz, got $sample"
    exit 1
  fi
done

# Now, offline all the CPUs in the emulated NUMA node.
for id in $cpus_to_offline; do
	echo 0 | sudo tee /sys/devices/system/cpu/cpu$id/online
	echo "offlined cpu$id on NUMA $max_numa_node"
done
