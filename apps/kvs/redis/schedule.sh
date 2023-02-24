#!/bin/bash
set -e

# create a stop button
RUNFILE=__running_${APP}__
touch ${RUNFILE}
check_for_stop() {
    # stop if the fd is removed
    if [ ! -f ${RUNFILE} ]; then 
        echo "stop requested"   
        exit 0
    fi
}

# Run a set of experiments
# OPS=10000000
# MAXRSS=565000000
OPS=100000
MAXRSS=62971904
# for memp in `seq 100 -5 5`; do
for memp in 20; do
    check_for_stop
    lmem=$(echo $memp $MAXRSS | awk '{ printf "%d", $1 * $2 / 100 }')
    echo "Profiling rocksdb - params: $MAXRSS, $memp, $lmem"
    bash trace.sh -ops=${OPS} -lm=$lmem -lmp=${memp} -d="fulltrace" --merge --analyze
done

rm -f ${RUNFILE}