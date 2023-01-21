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

# 1000 samples per sec
# bash trace.sh -ops=3000000 -lm=1000000000 -b=all -d="maxrss" -ms=10
# bash trace.sh -ops=30000000 -ms=1000 -lm=1000000000 -b=readseq
# bash trace.sh -ops=30000000 -ms=1000 -lm=1000000000 -b=readrandom
# bash trace.sh -ops=30000000 -ms=1000 -lm=1000000000 -b=readreverse

# record all samples
# bash trace.sh -ops=30000000 -lm=1000000000 -b=all
# bash trace.sh -ops=30000000 -lm=1000000000 -b=readseq
# bash trace.sh -ops=30000000 -lm=1000000000 -b=readrandom
# bash trace.sh -ops=30000000 -lm=1000000000 -b=readreverse

# mem percent 419
MAXRSS=419
# for memp in `seq 100 -5 5`; do
    check_for_stop
    lmem=$(echo $memp $MAXRSS | awk '{ printf "%d", $1 * $2 / 100 }')

    echo "Profiling rocksdb - params: $MAXRSS, $memp, $lmem"
    mem=$((lmem*1000000))
    bash trace.sh -ops=3000000 -lm=$((lmem*1024*1024)) -lmp=${memp} -b=all -d="trace" -ms=1000
done


rm -f ${RUNFILE}