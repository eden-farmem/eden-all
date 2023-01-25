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
for ops in `seq 1000000 1000000 10000000`; do
    check_for_stop
    bash trace.sh -ops=${ops} -d="test" -ms=1 
done

# OPS=1000000
# MAXRSS=87671360
# for memp in `seq 100 -5 5`; do
#     check_for_stop
#     lmem=$(echo $memp $MAXRSS | awk '{ printf "%d", $1 * $2 / 100 }')
#     echo "Profiling rocksdb - params: $MAXRSS, $memp, $lmem"
#     bash trace.sh -ops=${OPS} -lm=$lmem -lmp=${memp} -b=all -d="fulltrace" --merge --analyze
# done

rm -f ${RUNFILE}