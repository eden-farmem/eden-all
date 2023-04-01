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
MAXRSS=3199528960
for memp in `seq 100 -5 5`; do
# for memp in 10; do
    check_for_stop
    lmem=$(echo $memp $MAXRSS | awk '{ printf "%d", $1 * $2 / 100 }')
    echo "Profiling synthetic - params: $MAXRSS, $memp, $lmem"
    bash trace.sh -lm=$lmem -lmp=${memp} -d="trace" --merge --analyze
done

rm -f ${RUNFILE}