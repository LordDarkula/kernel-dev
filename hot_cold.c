// /tmp/hot_cold.c
#define _GNU_SOURCE
#include <numa.h>
#include <numaif.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sched.h>
#include <errno.h>

static void pin_to_node0(void) {
    // since we offline node1, we should pin to node0
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset); // clear CPU mask
    CPU_SET(0, &cpuset); // pin to CPU 0
    // first arg is pid (0 of this proc)
    if (sched_setaffinity(0, sizeof(cpuset), &cpuset) != 0) {
        perror("sched_setaffinity");
    }
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "Usage: %s <MiB_to_alloc> <node> <percent_to_touch>\n", argv[0]);
        return 1;
    }
    long sizeMiB = atol(argv[1]);
    if (sizeMiB <= 0) {
        fprintf(stderr, "sizeMiB must be > 0\n");
        return 1;
    }

    int node = atoi(argv[2]);
    if (node < 0 || node > 2) {
        fprintf(stderr, "node must be 0 or 1\n");
        return 1;
    }

    int percent = atoi(argv[3]);
    if (percent < 0 || percent > 100) {
        fprintf(stderr, "percent must be between 0 and 100");
        return 1;
    }

    if (numa_available() < 0) {
        fprintf(stderr, "NUMA not available\n");
        return 1;
    }

    pin_to_node0();

    size_t bytes = (size_t)sizeMiB * 1024ULL * 1024ULL;

    printf("Allocating %ld MiB on node %d...\n", sizeMiB, node);
    void *buf = numa_alloc_onnode(bytes, node);
    if (!buf) {
        perror("numa_alloc_onnode");
        return 1;
    }

    // Touch everything once → mapped & "hot" initially
    printf("Touching all pages once...\n");
    size_t page = 4096;
    for (size_t offset = 0; offset < bytes; offset += page) {
        ((char *)buf)[offset] = 1;
    }

    printf("Now keeping only 10%% of pages hot, letting 90%% go cold...\n");
    // Continuously touch only 1/10th of the range

    size_t hot_span = (bytes * (size_t)percent) / 100;
    while (1) {
        for (size_t offset = 0; offset < hot_span; offset += page) {
            ((char *)buf)[offset] ^= 1;
        }
        // sleep a bit to let kernel/Colloid age the rest
        usleep(200 * 1000); // 200 ms
    }

    // never reached
    // numa_free(buf, bytes);
    // return 0;
}
