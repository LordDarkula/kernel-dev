#!/bin/bash

# setup cgroup for hot-cold experiment

# run with
# sudo bash -c '
#   echo $$ > /sys/fs/cgroup/hot-cold-cg/cgroup.procs
#     exec ./hot_cold
#     '
set -o errexit
set -o pipefail
set -o nounset

readonly cg_root="/sys/fs/cgroup"
readonly tst_cg="$cg_root/hot-cold-cg"

readonly bytes_2_gib=$(echo "2^31" | bc)
readonly bytes_8_gib=$(echo "2^33" | bc)

echo "+cpuset" | sudo tee $cg_root/cgroup.subtree_control

sudo mkdir $tst_cg
echo $bytes_8_gib | sudo tee "$tst_cg/memory.max"
echo "0 $bytes_8_gib" | sudo tee "$tst_cg/memory.max_per_node"
echo "1 $bytes_2_gib" | sudo tee "$tst_cg/memory.max_per_node"
