# Setup Colloid Algorithm

After booting the colloid kernel, you must do the following steps in order to get Colloid running.

## Offlining CPUs on Far Tier
Run the script `mimic_cxl_numa.sh` which offlines all the CPUs on the highest NUMA node (index 1 on 2 NUMA machines)
to imitate the slower `FAR_MEM` tier.

> This step must be done before loading `tierinit` so it can collect latency stats correctly

## Colloid Modules
Colloid ships with the following kernel modules.

- `tierinit` initializes the colloid tiers on NUMA nodes
- `kswapdrst` swaps out pages to disk to prevent OOM (out of memory) errors
- `colloid-mon` spawns a kthread to monitor the usage on the memory bus
- `memeater` eats memory to help with experiments

Make all modules by entering `colloid/tpp/` and the module directory and running `make`.

Then load with the `insmod` command.
```bash
$ sudo insmod tierinit/tierinit.ko
```

You can unload a module with `rmmod`.
```bash
$ sudo rmmod tierinit
```

To load memeater, you ned to provide the number of pages and page size.
```bash
$ sudo insmod memeater/memeater.ko sizeMiB=4096 PGSIZE=4096 PGORDER=0
```

To check if the module is loaded
```bash
$ sudo lsmod | grep colloid-mon
```

## Enable Kernel features necessary for Colloid
Last, you must enable the following features.
> These features are provided by the base Linux kernel. Loading/unloading colloid-mon enables/disables Colloid.
```bash
$ sudo swapoff -a # Disable swap
$ echo 1 | sudo tee /sys/kernel/mm/numa/demotion_enabled # Enable page demotion
$ echo 6 | sudo tee /proc/sys/kernel/numa_balancing # Enable colloid
```

## Verify Colloid is working
To sanity-check, build and run `hot_cold.c`. It allocates memory on the close tier and keeps touching a subset (10%) of them.
The untouched 80% should be gradually offloaded to the far tier (CPU 1) over time to preserve the memory bandwidth.

Libnuma is required to allocate memory on specific NUMA nodes.
```bash
$ sudo apt-get install -y libnuma-dev
```

When compiling, `-lnuma` flag is essential.
```bash
 gcc -std=gnu11 -lnuma -o hot_cold hot_cold.c -lnuma
```

To verify, you must create memory on the slow tier (node 1) and touch some percent (ie. 10%) to watch it slowly migrate the hot pages to the fast tier (node 0).
> This only verifies page demotion and NUMA load balancing, not the Colloid functionality specifically
```bash
$  ./hot_cold 8000 1 10
```

To verify Colloid we must create contention on the memory bus for the fast tier (node 0) using `stress-ng`.

First install necessary software.
```bash
$ sudo apt install -y numactl stress-ng
```

This command creates `8096M` of contention on the bus.
```bash
$ numactl --cpunodebind=0 --membind=0   stress-ng --stream 4 --stream-l3-size 8096M --timeout 60s
```
You should see some of the hot memory remaining on the slow tier.

Watch the memory consumption of all NUMA nodes.

```bash
# keep executing
$ numastat -m
# to be fancy
$ watch -n 1 numastat -m
```

You can also check the memory usage of `hot_cold` specifically.

```bash
$ pidof hot_cold
$ numastat -p xxx
```
