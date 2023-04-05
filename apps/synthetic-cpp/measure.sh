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

## Workload (AIFM)
NKEYS=
NBLOBS=
EDEN_MAX=21824      # 21607+1%
FASTSWAP_MAX=
CORES=2
# ZIPFS=0.8

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
    "fswap")            MAXRSS=${FASTSWAP_MAX}; PINNED=$((cores*381));;
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
    if [ "$rdahead" == "1" ];   then  OPTS="$OPTS --rdahead"; fi
    if [[ $evictbs ]];          then  OPTS="$OPTS --batchevict=${evictbs}"; fi
    if [[ $evgens ]];           then  OPTS="$OPTS --evictgens=${evgens}"; fi
    if [[ $kpr ]];              then  OPTS="$OPTS --keyspreq=${kpr}"; fi
    if [[ $evprio ]];           then  OPTS="$OPTS --prio"; fi
    # OPTS="$OPTS --sampleepochs"
    # OPTS="$OPTS --safemode"
    # OPTS="$OPTS --pfsamples"
    rebuild_with_current_config
    echo $OPTS
    
    # run
    configure_max_local_mem "$kind" "$cores"
    # for memp in `seq 10 10 100`; do
    for memp in 50; do
        check_for_stop
        lmemopt=
        if [[ $MAXRSS ]]; then 
            lmem_mb=$(percentof "$MAXRSS" "$memp" | ftoi)
            if [[ $PINNED ]]; then lmem_mb=$((lmem_mb+PINNED)); fi
            lmem=$((lmem_mb*1024*1024))
            lmemopt="-lm=${lmem} -lmp=${memp}"
        fi
        echo bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG}             \
            -c=${cores} -t=${threads} -nk=${NKEYS} -nb=${NBLOBS}        \
            ${lmemopt} -zs=${zparams} ${NOPIE} -d="""${desc}"""
        bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG}                  \
            -c=${cores} -t=${threads} -nk=${NKEYS} -nb=${NBLOBS}        \
            ${lmemopt} -zs=${zparams} ${NOPIE} -d="""${desc}"""
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

# runs
rd=                     # use read-ahead hints
ebs=                    # set eviction batch size
evp=                    # set eviction policy
evg=4                   # set eviction gens
prio=                   # enable eviction priority
kpr=${KEYS_PER_REQ}     # keys per request
for c in ${CORES}; do
    desc="test"
    t=$((c*tpc))
    # run_vary_lmem "uthr"    "local" "$op" "$c" "$t" "$zs" "$rd" "$ebs" "$evp" "$evg" "$kpr" "$prio"
    # run_vary_lmem "eden-nh" "local" "$op" "$c" "$t" "$zs" "$rd" "$ebs" "$evp" "$evg" "$kpr" "$prio"
    run_vary_lmem "eden-bh" "local" "$op" "$c" "$t" "$zs" "$rd" "$ebs" "$evp" "$evg" "$kpr" "prio"
    # run_vary_lmem "eden-bh" "local" "$op" "$c" "$t" "$zs" "$rd" "$ebs" "NONE" "$evg" "$kpr" "yes"
    # run_vary_lmem "eden"    "local" "$op" "$c" "$t" "$zs" "$rd" "$ebs" "SC"   "$evg" "$kpr" "$prio"
done

# Fastswap runs

# cleanup
rm -f ${TEMP_PFX}*
rm -f __running__
