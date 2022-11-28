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
    "eden-nh")          OPTS="$OPTS --eden";;
    "eden")             OPTS="$OPTS --eden --hints";;
    "fswap")            OPTS="$OPTS --fastswap";;
    "fswap-uthr")       OPTS="$OPTS --fastswap --shenango";;
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

configure_max_local_mem() {
    local kind=$1
    local cores=$2
    case $kind in
    "pthr")             MAXRSS=6200;;
    "uthr")             MAXRSS=5700;;
    "eden-nh")          MAXRSS=5700;;
    "eden")             MAXRSS=5700;;
    "fswap")            MAXRSS=6150;    PINNED=$((cores*381));;
    "fswap-uthr")       MAXRSS=6150;    PINNED=$((cores*381));;
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

    # build 
    CFLAGS=
    OPTS=
    configure_for_fault_kind "$kind"
    configure_for_request_op "$op"
    configure_for_backend "$bkend"
    configure_for_evict_policy "$evp"
    if [ "$rdahead" == "1" ];   then  OPTS="$OPTS --rdahead"; fi
    if [[ $evictbs ]];          then  OPTS="$OPTS --batchevict=${evictbs}"; fi
    if [[ $evgens ]];           then  OPTS="$OPTS --evictgens=${evgens}"; fi
    # OPTS="$OPTS --sampleepochs"
    # OPTS="$OPTS --safemode"
    rebuild_with_current_config
    echo $OPTS
    
    # run
    configure_max_local_mem "$kind" "$cores"
    for memp in `seq 20 10 100`; do
    # for memp in 100; do
        check_for_stop
        lmem_mb=$(percentof "$MAXRSS" "$memp" | ftoi)
        if [[ $PINNED ]]; then lmem_mb=$((lmem_mb+PINNED)); fi
        lmem=$((lmem_mb*1024*1024))
        echo bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG}                  \
            -c=${cores} -t=${threads} -nk=${NKEYS} -nb=${NBLOBS}            \
            -lm=${lmem} -lmp=${memp} -zs=${zparams} ${NOPIE} -d="""${desc}"""
        bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG}                  \
            -c=${cores} -t=${threads} -nk=${NKEYS} -nb=${NBLOBS}        \
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

# eden runs
rd=         # use read-ahead hints
ebs=        # set eviction batch size
evp=        # set eviction policy
evg=        # set eviction gens
for op in "zip5"; do  # "zip5" "zip50" "zip500"; do
    for zs in 1; do
        for c in 1 5 12; do
            for tpc in 1; do
                desc="rdma"
                t=$((c*tpc))
                # run_vary_lmem "eden-nh" "local" "$op" "$c" "$t" "$zs" "$rd" "$ebs" "$evp" "$evg"
                # run_vary_lmem "eden"    "local" "$op" "$c" "$t" "$zs" "$rd" "$ebs" "NONE" "$evg"
                # run_vary_lmem "eden"    "local" "$op" "$c" "$t" "$zs" "$rd" "8" "NONE" "$evg"
                # run_vary_lmem "eden"    "local" "$op" "$c" "$t" "$zs" "$rd" "$ebs" "SC" "$evg"
                # run_vary_lmem "eden"    "local" "$op" "$c" "$t" "$zs" "$rd" "$ebs" "LRU" "$evg"
                # run_vary_lmem "eden-nh" "rdma"  "$op" "$c" "$t" "$zs" "$rd" "$ebs" "$evp" "$evg"
                # run_vary_lmem "eden"    "rdma"  "$op" "$c" "10" "$zs" "$rd" "$ebs" "NONE" "$evg"
                # run_vary_lmem "eden"    "rdma"  "$op" "$c" "50" "$zs" "$rd" "$ebs" "NONE" "$evg"
                # run_vary_lmem "eden"    "rdma"  "$op" "$c" "50" "$zs" "$rd" "8" "NONE" "$evg"

                # run_vary_lmem "fswap"    "local"  "$op" "$c" "$t" "$zs" "$rd" "$ebs" "$evp" "$evg"
                run_vary_lmem "fswap"    "rdma"  "$op" "$c" "$t" "$zs" "$rd" "$ebs" "$evp" "$evg"
            done
        done
    done
done

# Fastswap runs

# cleanup
rm -f ${TEMP_PFX}*
rm -f __running__
