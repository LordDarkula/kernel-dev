#!/bin/bash

# enables Colloid modules (assumes we are running on colloid kernel)
set -o errexit
set -o pipefail
set -o nounset

echo "Remember to run mimic_cxl_numa.sh to offline NUMA 1."

cd colloid/tpp/

# Build colloid modules
cd tierinit
make
cd ..

cd kswapdrst
make
cd ..

cd colloid-mon
make
cd ..

# enable colloid modules
sudo insmod tierinit/tierinit.ko
sudo insmod kswapdrst/kswapdrst.ko

if ! sudo insmod colloid-mon/colloid-mon.ko; then
  echo "[warn] colloid-mon already loaded or failed to load; continuing"
fi

# enable colloid features
sudo swapoff -a # Disable swap
echo 1 | sudo tee /sys/kernel/mm/numa/demotion_enabled # Enable page demotion
echo 6 | sudo tee /proc/sys/kernel/numa_balancing # Enable colloid
