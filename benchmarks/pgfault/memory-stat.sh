

#!/bin/bash

#
# Collect cgroup stats for Fastswap
#

APPNAME=$1
while true
do
    cat /cgroup2/benchmarks/$APPNAME/memory.stat                \
        | awk '{ printf "%s:%s,", $1, $2 } END { printf "\n" }' \
        | ts %s, >> memory-stat.out
    sleep 1
done