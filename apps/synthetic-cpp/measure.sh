#!/bin/bash
# set -e

#
# Run synthetic benchmark in various settings
# 

usage="\n
-d, --debug \t\t build debug\n
-t, --trace \t\t run with fault tracing\n
-g, --gdb \t\t run with gdb\n
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

source ${ROOTDIR}/scripts/utils.sh

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -t|--trace)
    TRACE=1
    ;;

    -g|--gdb)
    GDBOPT="-g"
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

## Workload (Debug)
# CORES=1
# THREADS=40
# HASH_POWER_SHIFT=20
# NUM_ARRAY_ENTRIES="(2<<15)"
# KVENTRIES_SHIFT=19
# VALUE_SIZE=4
# EDEN_MAX=106
# FASTSWAP_MAX=
# ZIPFS=0.85
# KPR=32

## Workload (AIFM)
CORES=10     # was 10
THREADS=40
HASH_POWER_SHIFT=28
NUM_ARRAY_ENTRIES="(2<<20)"
KVENTRIES_SHIFT=27
VALUE_SIZE=4
EDEN_MAX=26890      #+1% EvT?
FASTSWAP_MAX=26990
KPR=32
ZIPFS=0.85
INIT_ARRAY=1

## use below params for maxrss
# ZIPFS=0.1

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
    "uthr")             OPTS="$OPTS ";;
    "eden-nh")          OPTS="$OPTS --eden";;
    "eden-bh")          OPTS="$OPTS --eden --bhints";;
    "eden")             OPTS="$OPTS --eden --hints";;
    "fswap")            OPTS="$OPTS --fastswap";;
    *)                  echo "Unknown fault kind"; exit;;
    esac
}

configure_for_backend() {
    local bkend=$1
    case $bkend in
    "")                 ;;
    "local")            OPTS="$OPTS --bkend=local";;
    "rdma")             OPTS="$OPTS --bkend=rdma";;
    *)                  echo "Unknown backend"; exit;;
    esac
}

configure_max_local_mem() {
    local kind=$1
    local cores=$2
    case $kind in
    "uthr")             MAXRSS=;;
    "eden-nh")          MAXRSS=${EDEN_MAX};;
    "eden-bh")          MAXRSS=${EDEN_MAX};;
    "eden")             MAXRSS=${EDEN_MAX};;
    "fswap")            MAXRSS=${FASTSWAP_MAX};;
    *)                  echo "Unknown fault kind"; exit;;
    esac
}

configure_for_evict_policy() {
    local evp=$1
    case $evp in
    "")                 ;;
    "NONE")             ;;
    "LRU")              OPTS="$OPTS --evictpolicy=LRU";;
    "SC")               OPTS="$OPTS --evictpolicy=SC";;
    *)                  echo "Unknown evict policy"; exit;;
    esac
}

rebuild_with_current_config() {
    bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG} --force --buildonly ${NOPIE}
}

run_vary_lmem() {
    local kind=$1
    local bkend=$2
    local op=$3
    local cores=$4
    local threads=$5
    local zparams=$6
    local rdahead=$7
    local evictbs=$8
    local evp=$9
    local evgens=${10}
    local kpr=${11}
    local evprio=${12}

    # build 
    CFLAGS=
    OPTS=
    configure_for_fault_kind "$kind"
    configure_for_backend "$bkend"
    configure_for_evict_policy "$evp"
    if [ "$rdahead" == "1" ];   then  OPTS="$OPTS --rdahead";               fi
    if [[ $evictbs ]];          then  OPTS="$OPTS --batchevict=${evictbs}"; fi
    if [[ $evgens ]];           then  OPTS="$OPTS --evictgens=${evgens}";   fi
    if [[ $kpr ]];              then  OPTS="$OPTS --keyspreq=${kpr}";       fi
    if [[ $evprio ]];           then  OPTS="$OPTS --prio";                  fi    
    if [[ $TRACE ]];            then  OPTS="$OPTS --pfsamples";             fi
    if [[ $INIT_ARRAY ]];       then  OPTS="$OPTS --initarray";             fi
    OPTS="$OPTS -hp=${HASH_POWER_SHIFT} -nae=${NUM_ARRAY_ENTRIES}"
    OPTS="$OPTS -vs=${VALUE_SIZE} -kes=${KVENTRIES_SHIFT}"
    OPTS="$OPTS -t=${threads} -zs=${zparams}"
    # OPTS="$OPTS --priotype=EXPONENTIAL"
    # OPTS="$OPTS --sampleepochs"
    # OPTS="$OPTS --safemode"
    # OPTS="$OPTS --pfsamples"
    rebuild_with_current_config
    echo $OPTS
    
    # run
    configure_max_local_mem "$kind" "$cores"
    # for memp in `seq 10 10 100`; do
    # for memp in 4 8 16 22 33 41 50 58 66 75 83 91 100; do
    # for memp in 100 91 83 75 66 58 50 41 33 22 16 8 4; do
    for memp in 10; do
        check_for_stop
        lmemopt=
        if [[ $MAXRSS ]]; then 
            lmem_mb=$(percentof "$MAXRSS" "$memp" | ftoi)
            lmem=$((lmem_mb*1024*1024))
            lmemopt="-lm=${lmem} -lmp=${memp}"
        fi

        echo bash run.sh ${OPTS} -c="$cores" -fl="""$CFLAGS""" ${GDBOPT} ${lmemopt} -d="""${desc}"""
        bash run.sh ${OPTS} -c="$cores" -fl="""$CFLAGS""" ${GDBOPT} ${lmemopt} -d="""${desc}"""
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
    for cores in 1 2 3 4 5; do 
        check_for_stop
        threads=$((cores*thrpc))
        bash run.sh ${OPTS} -fl="""$CFLAGS""" ${GDBOPT} -c=${cores} -t=${threads}    \
            -nk=${NKEYS} -nb=${NBLOBS} -zs=${zparams} ${GDBOPT} -d="""${desc}"""
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

# runs
rd=                     # use read-ahead hints
ebs=                    # set eviction batch size
evp=                    # set eviction policy
evg=4                   # set eviction gens
prio=                   # enable eviction priority
desc="test"

## basic
# run_vary_lmem "uthr"    "local" "$op" "$CORES" "$THREADS" "$ZIPFS" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"
# run_vary_lmem "eden-nh" "local" "$op" "$CORES" "$THREADS" "$ZIPFS" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"
# run_vary_lmem "eden-bh" "local" "$op" "$CORES" "$THREADS" "$ZIPFS" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"

## prio
for try in 1 2 3; do
# for vs_kent in 4,27 1600,21 3200,20; do 
# for vs_kent in 4,27; do 
# VALUE_SIZE=$(echo $vs_kent | cut -d, -f1)
# KVENTRIES_SHIFT=$(echo $vs_kent | cut -d, -f2)
echo "VALUE_SIZE=$VALUE_SIZE KVENTRIES_SHIFT=$KVENTRIES_SHIFT"
# run_vary_lmem "uthr"    "local" "$op" "$CORES" "$THREADS" "$ZIPFS" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"
# run_vary_lmem "eden-bh" "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "1"   "32"   "SC"   "$evg" "$KPR" "yes"
# run_vary_lmem "eden"    "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "1"   "32"   "SC"   "$evg" "$KPR" "yes"
# run_vary_lmem "eden-bh" "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "1"   "32"   "$evp" "$evg" "$KPR" "$prio"
# run_vary_lmem "eden-bh" "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "1"   "32"   "$evp" "$evg" "$KPR" "yes"
# run_vary_lmem "eden-bh" "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "1"   "32"   "SC"   "$evg" "$KPR" "$prio"
# run_vary_lmem "eden-bh" "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "1"   "32"   "SC"   "$evg" "$KPR" "$prio"
# run_vary_lmem "eden"    "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "1"   "32"   "NONE"   "$evg" "$KPR" "yes"
# run_vary_lmem "fswap" "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"
# run_vary_lmem "eden-nh"   "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"
# run_vary_lmem "eden"    "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "1"   "32"   "NONE"   "$evg" "$KPR" "yes"
done
done

## vary zipfs
# run_vary_lmem "eden-bh" "rdma" "$op" "$CORES" "$THREADS" "0.5" "1"   "32"   "$evp" "$evg" "$KPR" "yes"

# Fastswap runs
# for try in 1 2 3 4 5; do
# run_vary_lmem "uthr" "local" "$op" "$CORES" "$THREADS" "$ZIPFS" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"
# run_vary_lmem "uthr" "local" "$op" "$CORES" "$THREADS" "0.5" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"
# run_vary_lmem "fswap" "rdma" "$op" "$CORES" "$THREADS" "$ZIPFS" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"
# run_vary_lmem "fswap" "rdma" "$op" "$CORES" "$THREADS" "0.5" "$rd" "$ebs" "$evp" "$evg" "$KPR" "$prio"
# done

# cleanup
rm -f ${TEMP_PFX}*
rm -f __running__
