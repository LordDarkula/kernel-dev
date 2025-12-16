#!/bin/bash

# enables Colloid modules (assumes we are running on colloid kernel)
set -o errexit
set -o pipefail
set -o nounset

# setup far tier on node 1
chmod +x mimic_cxl_numa.sh
sudo mimic_cxl_numa.sh

sudo insmod colloid/tpp/tierinit/tierinit.ko
sudo insmod colloid/tpp/kswapdrst/kswapdrst.ko
sudo insmod colloid/tpp/colloid-mon/colloid-mon.ko
