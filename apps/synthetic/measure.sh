#!/bin/bash
# set -e

#
# Run synthetic benchmark in various settings
# 

usage="\n
-w, --warmup \t run warmup for a few seconds before taking measurement\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
TEMP_PFX=tmp_msyn_
PLOTSRC=${SCRIPT_DIR}/../scripts/plot.py
ROOTDIR=${SCRIPT_DIR}/../..
PLOTDIR=plots 
DATADIR=data
PLOTEXT=png
WARMUP=1
WFLAG="--warmup"
# NOPIE="--nopie"   #debug

source ${ROOTDIR}/scripts/utils.sh

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
    ;;
    
    -w|--warmup)
    WARMUP=1
    WFLAG="--warmup"
    ;;

    -h | --help)
    echo -e $usage
    exit
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# settings
mkdir -p $DATADIR
MAX_MOPS=50000000   
NKEYS=10000000      # 2.5 GB
NBLOBS=400000       # 3 GB
lmem=1000000000     # 1 GB
cores=1
thr=1
sample=1
zparams=0.1         # uniform

# create a stop button
touch __running__
check_for_stop() {
    # stop if the fd is removed
    if [ ! -f __running__ ]; then 
        echo "stop requested"   
        exit 0
    fi
}

configure_for_fault_kind() {
    local kind=$1
    case $kind in
    "pthr")             ;;
    "uthr")             OPTS="$OPTS --shenango";;
    "kona-pthr")        OPTS="$OPTS --with-kona";;
    "kona-uthr")        OPTS="$OPTS --shenango --with-kona";;
    "sync")             OPTS="$OPTS --shenango --with-kona --pgfaults=SYNC";;
    "async")            OPTS="$OPTS --shenango --with-kona --pgfaults=ASYNC";;
    *)                  echo "Unknown fault kind"; exit;;
    esac
}

configure_for_request_op() {
    local op=$1
    case $op in
    "ht")                                                       LS=solid;   CMI=0;;
    "zip")              CFLAGS="$CFLAGS -DCOMPRESS=1";          LS=solid;   CMI=1;;
    "zip5")             CFLAGS="$CFLAGS -DCOMPRESS=5";          LS=solid;   CMI=1;;
    "zip50")            CFLAGS="$CFLAGS -DCOMPRESS=50";         LS=solid;   CMI=1;;
    "zip500")           CFLAGS="$CFLAGS -DCOMPRESS=500";        LS=solid;   CMI=1;;
    "enc")              CFLAGS="$CFLAGS -DENCRYPT";             LS=dashdot; CMI=1;;
    "enc+zip")          CFLAGS="$CFLAGS -DCOMPRESS -DENCRYPT";  LS=dotted;  CMI=1;;
    *)                  echo "Unknown op"; exit;;
    esac
}

configure_for_pgchecks_type() {
    local pgchecks=$1
    case $pgchecks in
    "vdso")             ;;
    "kona")             OPTS="$OPTS --kona-page-checks";;
    *)                  echo "Unknown page check type"; exit;;
    esac
}

configure_max_local_mem() {
    local kind=$1
    case $kind in
    "pthr")             MAXRSS=;;
    "uthr")             MAXRSS=;;
    "kona-pthr")        MAXRSS=6200;;
    "kona-uthr")        MAXRSS=5700;;
    "sync")             MAXRSS=5700;;
    "async")            MAXRSS=5700;;
    *)                  echo "Unknown fault kind"; exit;;
    esac
}

rebuild_with_current_config() {
    bash run.sh ${OPTS} -fl="""$CFLAGS""" -ko=${KCFLAGS} ${WFLAG}   \
        --force --buildonly ${NOPIE}
}

run_vary_lmem() {
    local kind=$1
    local op=$2
    local cores=$3
    local threads=$4
    local zparams=$5
    local pgchecks=$6

    # build 
    CFLAGS=
    OPTS=
    configure_for_fault_kind "$kind"
    configure_for_request_op "$op"
    configure_for_pgchecks_type "$pgchecks"
    rebuild_with_current_config
    
    # run
    configure_max_local_mem "$kind"
    for memp in `seq 20 10 100`; do 
    # for memp in 50; do
        check_for_stop
        lmem_mb=$(percentof "$MAXRSS" "$memp" | ftoi)
        lmem=$((lmem_mb*1024*1024))
        bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG} -ko=${KCFLAGS}   \
                -c=${cores} -t=${threads} -nk=${NKEYS} -nb=${NBLOBS}    \
                -lm=${lmem} -lmp=${memp} -zs=${zparams} ${NOPIE} -d="""${desc}"""
    done
}

run_vary_cores() {
    kind=$1
    op=$2
    zparams=$3
    thrpc=$4

    # build 
    CFLAGS=
    OPTS=
    configure_for_fault_kind "$kind"
    configure_for_request_op "$op"
    rebuild_with_current_config

    # run
    # for cores in 1 2 3 4 5; do 
    for cores in 1; do 
        check_for_stop
        threads=$((cores*thrpc))
        bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG} -c=${cores} -t=${threads}    \
            -nk=${NKEYS} -nb=${NBLOBS} -zs=${zparams} ${NOPIE} -d="""${desc}"""
    done
}

run_vary_thr_per_core() {
    kind=$1
    op=$2
    zparams=$3
    cores=$4

    # build 
    CFLAGS=
    OPTS=
    configure_for_fault_kind "$kind"
    configure_for_request_op "$op"
    rebuild_with_current_config

    # run
    for tpc in `seq 1 5 100`; do
        check_for_stop
        threads=$((cores*tpc))
        bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG}                  \
                -c=${cores} -t=${threads} -nk=${NKEYS} -nb=${NBLOBS}    \
                -zs=${zparams} ${NOPIE} -d="""${desc}"""
    done
}

# kona runs
c=1
for op in "zip5"; do  # "zip5" "zip50" "zip500"; do
    for zs in 0.1 1; do 
        # for c in `seq 1 1 2`; do
        # for try in 1; do
        for tpc in 5 20; do
            desc="secondchance"
            KCFLAGS="-DSECOND_CHANCE_EVICTION"
            t=$((c*tpc))
            kt=$((c*tpc))
            # run_vary_lmem "kona-pthr"       $op $c $kt $zs "vdso"
            # run_vary_lmem "kona-uthr"       $op $c $t $zs "vdso"
            # run_vary_lmem "async"           $op $c $t $zs "vdso"
            run_vary_lmem "async"           $op $c $t $zs "kona"
        done
    done
done

# # no-kona runs with varying cores
# tpc=10
# for op in "zip5"; do  # "zip5" "zip50" "zip500"; do
#     for zs in 1; do 
#         desc="${op}-vanilla"
#         # run_vary_cores "pthr" $op $zs $tpc
#         run_vary_cores "uthr"   $op $zs $tpc
#     done
# done

# # no-kona runs with different concur
# cores=4
# op="zip"    # "zip5" "zip50" "zip500"    
# desc="varyconcur-${op}"
# for zs in 0.1 1; do
#     run_vary_thr_per_core "pthr" $op $zs $cores
#     run_vary_thr_per_core "uthr" $op $zs $cores
# done

# cleanup
rm -f ${TEMP_PFX}*
rm -f __running__
