#!/bin/bash

# enables page demotion and NUMA load balancing for TPP functionality
set -o errexit
set -o pipefail
set -o nounset

sudo swapoff -a
echo 1 | sudo tee /sys/kernel/mm/numa/demotion_enabled
echo 1 | sudo tee /proc/sys/kernel/numa_balancing
