# Setup Colloid Algorithm

After booting the colloid kernel, you must do the following steps in order to get Colloid running.

Run the script `mimic_cxl_numa.sh` which offlines all the CPUs on the highest NUMA node (index 1 on 2 NUMA machines)
to imitate the slower `FAR_MEM` tier.

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

Last, you must enable the features of colloid.
```bash
$ sudo swapoff -a # Disable swap
$ echo 1 > sudo /sys/kernel/mm/numa/demotion_enabled # Enable page demotion
$ echo 6 > sudo /proc/sys/kernel/numa_balancing # Enable colloid
```

