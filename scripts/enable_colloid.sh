#!/bin/bash

# enables Colloid modules (assumes we are running on colloid kernel)
set -o errexit
set -o pipefail
set -o nounset

echo "Remember to run mimic_cxl_numa.sh to offline NUMA 1."

cd colloid/tpp/

cd tierinit
make
cd ..

cd kswapdrst
make
cd ..

cd colloid-mon
make
cd ..

sudo insmod tierinit/tierinit.ko
sudo insmod kswapdrst/kswapdrst.ko
sudo insmod colloid-mon/colloid-mon.ko
