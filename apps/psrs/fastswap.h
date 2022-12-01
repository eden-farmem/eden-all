/**
 * fastswap.h - Fastswap-specific support
 * NOTE: the cgroup names are hard-coded
 */

#ifndef __FASTSWAP_H__
#define __FASTSWAP_H__

#define FASTSWAP_CGROUP_APP "synthetic"

static inline void set_local_memory_limit(unsigned long limit)
{
    char buf[256];
    sprintf(buf, "echo %lu > /cgroup2/benchmarks/%s/memory.high", 
        limit, FASTSWAP_CGROUP_APP);
    system(buf);
}

/* get current memory usage for a cgroup2 app */
static inline unsigned long get_memory_usage(char* appname)
{
    char fname[256];
    FILE *fp;
    unsigned long usage;

    sprintf(fname, "/cgroup2/benchmarks/%s/memory.current", FASTSWAP_CGROUP_APP);
    fp = fopen(fname, "r");
    if (fp == NULL) {
      printf("ERROR! Failed to get memory usage\n");
      exit(1);
    }
    fscanf(fp, "%lu", &usage);
    fclose(fp);
    return usage;
}

#endif // __FASTSWAP_H__