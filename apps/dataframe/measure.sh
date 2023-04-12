#!/bin/bash
set -e

#
# Run sort benchmark in various settings
# 

usage="\n
-f, --force \t\t force re-run experiments\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
ROOTDIR=${SCRIPT_DIR}/../..
TMP_PFX=tmp_sort

source ${ROOTDIR}/scripts/utils.sh

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -f|--force)
    FORCE=1
    FFLAG="--force"
    ;;
    
    -t|--trace)
    TRACE=1
    ;;

    -h | --help)
    echo -e $usage
    exit
    ;;

    *)                      # unknown option
    echo "Unknown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# Configs

## Debug/Quick
# INPUT=debug
# FASTSWAP_MAX=
# EDEN_MAX=1

## Small
# INPUT=small
# FASTSWAP_MAX=
# EDEN_MAX=3077     #3076+1%EvT

## Large
INPUT=large
FASTSWAP_MAX=
EDEN_MAX=30000

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
    "eden-bh")          OPTS="$OPTS --eden --bhints";;
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

configure_max_local_mem() {
    local kind=$1
    local cores=$2
    case $kind in
    "pthr")             MAXRSS=;;
    "uthr")             MAXRSS=;;
    "eden-nh")          MAXRSS=${EDEN_MAX};;
    "eden-bh")          MAXRSS=${EDEN_MAX};;
    "eden")             MAXRSS=${EDEN_MAX};;
    "fswap")            MAXRSS=${FASTSWAP_MAX};;
    "fswap-uthr")       MAXRSS=${FASTSWAP_MAX};;
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
    bash run.sh ${OPTS} ${WFLAG} --force --buildonly ${NOPIE}
}

run_vary_lmem() {
    local kind=$1
    local bkend=$2
    local cores=$3
    local threads=$4
    local rdahead=$5
    local evictbs=$6
    local evp=$7
    local evgens=$8

    # build 
    CFLAGS=
    OPTS=
    configure_for_fault_kind "$kind"
    configure_for_backend "$bkend"
    configure_for_evict_policy "$evp"
    if [[ $rdahead ]];  then  OPTS="$OPTS --rdahead=${rdahead}";    fi
    if [[ $evictbs ]];  then  OPTS="$OPTS --batchevict=${evictbs}"; fi
    if [[ $evgens ]];   then  OPTS="$OPTS --evictgens=${evgens}";   fi
    if [[ $INPUT ]];    then  OPTS="$OPTS --input=${INPUT}";        fi
    if [[ $TRACE ]];    then  OPTS="$OPTS --pfsamples";                 fi
    # OPTS="$OPTS --sampleepochs"
    # OPTS="$OPTS --safemode"
    rebuild_with_current_config
    echo $OPTS
    
    # run
    configure_max_local_mem "$kind" "$cores"
    # for memp in `seq 10 10 100`; do
    for memp in 150; do
        check_for_stop
        lmemopt=
        if [[ $MAXRSS ]]; then 
            lmem_mb=$(percentof "$MAXRSS" "$memp" | ftoi)
            lmem=$((lmem_mb*1024*1024))
            lmemopt="-lm=${lmem} -lmp=${memp}"
        fi
        echo bash run.sh -c=${cores} -t=${threads} ${OPTS} ${FFLAG} -d="""${desc}""" ${lmemopt}
        bash run.sh -c=${cores} -t=${threads} ${OPTS} ${FFLAG} -d="""${desc}""" ${lmemopt}
    done
}

# defaults
rd=         # set custom read-ahead
ebs=        # set eviction batch size
evp=        # set eviction policy
evg=        # set eviction gens
desc="test"

# eden runs
# run_vary_lmem "pthr" "local" 1 1 "$rd" "$ebs" "$evp" "$evg"
# TRACE=1
run_vary_lmem "eden-nh" "local" 1 1 "$rd" "$ebs" "$evp" "$evg"
# TRACE=
# run_vary_lmem "eden-bh" "local" 1 1 "$rd" "$ebs" "$evp" "$evg"

# run_vary_lmem "eden-nh" "rdma"  1 1 "$rd" "$ebs" "$evp" "$evg"

# cleanup
rm -f ${TMP_PFX}*
rm -f __running__