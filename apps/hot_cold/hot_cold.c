#define _GNU_SOURCE
#include <errno.h>
#include <linux/mempolicy.h>
#include <numa.h>
#include <numaif.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>


#define HOT_TOUCH_SLEEP_US 200 * 1000


static void pin_to_numa_node_cpus(int node) {
    struct bitmask *cpus = numa_allocate_cpumask();
    if (!cpus) {
        perror("numa_allocate_cpumask");
        exit(1);
    }

    if (numa_node_to_cpus(node, cpus) != 0) {
        /* libnuma returns -1 on error, but errno is not always useful here. */
        fprintf(stderr, "numa_node_to_cpus(%d) failed\n", node);
        exit(1);
    }

    cpu_set_t set;
    CPU_ZERO(&set);

    int any = 0;
    for (unsigned i = 0; i < cpus->size; i++) {
        if (numa_bitmask_isbitset(cpus, i)) {
            CPU_SET((int)i, &set);
            any = 1;
        }
    }

    if (!any) {
        fprintf(stderr, "No CPUs found for NUMA node %d\n", node);
        exit(1);
    }

    if (sched_setaffinity(0, sizeof(set), &set) != 0) {
        perror("sched_setaffinity");
        exit(1);
    }

    numa_free_cpumask(cpus);
}

static void set_mem_policy_bind_node(int node) {
    struct bitmask *nodes = numa_allocate_nodemask();
    if (!nodes) {
        perror("numa_allocate_nodemask");
        exit(1);
    }

    numa_bitmask_clearall(nodes);
    numa_bitmask_setbit(nodes, node);

    /* maxnode is the number of bits in the nodemask. */
    unsigned long maxnode = nodes->size;

    if (set_mempolicy(MPOL_BIND, nodes->maskp, maxnode) != 0) {
        perror("set_mempolicy(MPOL_BIND)");
        exit(1);
    }

    numa_free_nodemask(nodes);
}

static void reset_mem_policy_default(void) {
    if (set_mempolicy(MPOL_DEFAULT, NULL, 0) != 0) {
        perror("set_mempolicy(MPOL_DEFAULT)");
        exit(1);
    }
}

static void touch_range(char *buf, size_t bytes, size_t page) {
    for (size_t off = 0; off < bytes; off += page) {
        buf[off] ^= 1;
    }
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "Usage: %s <MiB_to_alloc> <alloc_node> <percent_hot>\n", argv[0]);
        fprintf(stderr, "Example: %s 32768 1 25\n", argv[0]);
        return 1;
    }

    long sizeMiB = atol(argv[1]);
    int alloc_node = atoi(argv[2]);
    int percent_hot = atoi(argv[3]);

    if (sizeMiB <= 0) {
        fprintf(stderr, "MiB_to_alloc must be > 0\n");
        return 1;
    }
    if (percent_hot < 0 || percent_hot > 100) {
        fprintf(stderr, "percent_hot must be in [0,100]\n");
        return 1;
    }

    if (numa_available() < 0) {
        fprintf(stderr, "NUMA not available\n");
        return 1;
    }

    int maxnode = numa_max_node();
    if (alloc_node < 0 || alloc_node > maxnode) {
        fprintf(stderr, "alloc_node must be in [0,%d]\n", maxnode);
        return 1;
    }

    /* Run the hot loop on node 0 CPUs so AutoNUMA prefers node 0. */
    pin_to_numa_node_cpus(/*node=*/0);

    size_t bytes = (size_t)sizeMiB * 1024ULL * 1024ULL;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);

    printf("Allocating %ld MiB; forcing initial placement on NUMA node %d\n", sizeMiB, alloc_node);

    /* Phase 1: allocate on alloc_node and materialize the pages there. */
    set_mem_policy_bind_node(alloc_node);

    char *buf = (char *)malloc(bytes);
    if (!buf) {
        perror("malloc");
        return 1;
    }

    printf("Touching 100%% once to materialize pages on node %d...\n", alloc_node);
    touch_range(buf, bytes, page);

    /* Phase 2: restore the default policy so AutoNUMA may migrate pages. */
    reset_mem_policy_default();

    size_t hot_bytes = (bytes * (size_t)percent_hot) / 100;
    printf("Hot set: %d%% (%.2f GiB). Cold set: %d%% (%.2f GiB).\n",
           percent_hot, (double)hot_bytes / (1024.0 * 1024.0 * 1024.0),
           100 - percent_hot, (double)(bytes - hot_bytes) / (1024.0 * 1024.0 * 1024.0));

    printf("Looping: touching hot set\n");

    time_t start = time(NULL);
    if (start == (time_t)-1) {
        perror("time");
        free(buf);
        return 1;
    }

    while (1) {
        touch_range(buf, hot_bytes, page);
        usleep(HOT_TOUCH_SLEEP_US);
    }
}
