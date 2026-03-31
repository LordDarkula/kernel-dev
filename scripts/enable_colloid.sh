#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

echo "Remember to run offline_cpus_on_numa_node.sh <numa-node> before enabling Colloid."

cd colloid/tpp/

# Build colloid modules
cd tierinit && make && cd ..
cd kswapdrst && make && cd ..
cd colloid-mon && make && cd ..

# enable colloid modules
sudo insmod tierinit/tierinit.ko
sudo insmod kswapdrst/kswapdrst.ko

if ! sudo insmod colloid-mon/colloid-mon.ko; then
  echo "[warn] colloid-mon already loaded or failed to load; continuing"
fi

# Helper: write a value to a sysfs/proc file without killing the script
write_knob() {
  local value="$1"
  local path="$2"

  if [[ ! -e "$path" ]]; then
    echo "[warn] knob missing: $path (skipping)"
    return 0
  fi

  if ! echo "$value" | sudo tee "$path" >/dev/null; then
    echo "[warn] failed to write '$value' to $path (skipping)"
    return 0
  fi

  echo "[info] set $path = $value"
}

# enable colloid features
sudo swapoff -a || echo "[warn] swapoff failed (continuing)"

write_knob 1 /sys/kernel/mm/numa/demotion_enabled
write_knob 6 /proc/sys/kernel/numa_balancing
