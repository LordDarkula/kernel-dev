#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

readonly cg_root="/sys/fs/cgroup"
readonly tst_cg="$cg_root/hot-cold-cg"

# Make the mountpoint if it doesn't exist
mkdir -p "$cg_root"

# Mount cgroup2 there
mount -t cgroup2 none "$cg_root"
mount -o remount,rw "$cg_root"

/bin/echo +memory > $cg_root/cgroup.subtree_control


readonly bytes_32_gib=$(echo "2^35" | bc)
readonly bytes_64_gib=$(echo "2^36" | bc)

echo "+cpuset" | tee $cg_root/cgroup.subtree_control

mkdir -p $tst_cg
echo $bytes_64_gib | tee "$tst_cg/memory.max"
echo "0 $bytes_32_gib" | tee "$tst_cg/memory.max_per_node"
echo "1 $bytes_64_gib" | tee "$tst_cg/memory.max_per_node"
