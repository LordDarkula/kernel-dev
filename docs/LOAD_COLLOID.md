# Setup Colloid Algorithm

After booting the colloid kernel, you must do the following steps in order to get Colloid running.

## Offlining CPUs on Far Tier
Run the script `mimic_cxl_numa.sh` which offlines all the CPUs on the highest NUMA node (index 1 on 2 NUMA machines)
to imitate the slower `FAR_MEM` tier.

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

## Enable Colloid features
Last, you must enable the features of colloid.
```bash
$ sudo swapoff -a # Disable swap
$ echo 1 > sudo /sys/kernel/mm/numa/demotion_enabled # Enable page demotion
$ echo 6 > sudo /proc/sys/kernel/numa_balancing # Enable colloid
```

## Verify Colloid is working
To sanity-check, build and run `hot_cold.c`. It allocates memory on the close tier and keeps touching a subset (20%) of them.
The untouched 80% should be gradually offloaded to the far tier (CPU 1) over time to preserve the memory bandwidth.

Libnuma is required to allocate memory on specific NUMA nodes.
```bash
$ sudo apt-get install -y libnuma-dev
```

When compiling, `-lnuma` flag is essential.
```bash
 gcc -std=gnu11 -lnuma -o hot_cold hot_cold.c -lnuma
```

To verify, you must allocate enough memory to crowd the bus.
```bash
$  ./hot_cold 80000
```

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
