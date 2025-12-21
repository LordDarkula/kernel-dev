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

readonly bytes_2_gib=$(echo "2^31" | bc)
readonly bytes_4_gib=$(echo "2^32" | bc)

echo "+cpuset" | tee $cg_root/cgroup.subtree_control

mkdir -p $tst_cg
echo $bytes_4_gib | tee "$tst_cg/memory.max"
echo "0 $bytes_2_gib" | tee "$tst_cg/memory.max_per_node"
echo "1 $bytes_2_gib" | tee "$tst_cg/memory.max_per_node"
