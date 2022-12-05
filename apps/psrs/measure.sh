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

# Configs

# Small
# NKEYS=1000000000        # 4 GB input
# FASTSWAP_MAX=7500
# EDEN_MAX=7500   # TBD
# CORES=5

# Large
NKEYS=3000000000        # ~12 GB input, 25GB working set
FASTSWAP_MAX=23904
EDEN_MAX=25000          # TBD
CORES=10

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
    "eden-nqh")         OPTS="$OPTS --eden --hints"; CFLAGS="$CFLAGS -DNO_QSORT_ANNOTS";;
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
    bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG} --force --buildonly ${NOPIE}
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
    if [[ $rdahead ]];  then  OPTS="$OPTS --rdahead=${rdahead}"; fi
    if [[ $evictbs ]];  then  OPTS="$OPTS --batchevict=${evictbs}"; fi
    if [[ $evgens ]];   then  OPTS="$OPTS --evictgens=${evgens}"; fi
    # OPTS="$OPTS --sampleepochs"
    # OPTS="$OPTS --safemode"
    rebuild_with_current_config
    echo $OPTS
    
    # run
    configure_max_local_mem "$kind" "$cores"
    # for memp in `seq 20 10 100`; do
    for memp in 10; do
        check_for_stop
        lmemopt=
        if [[ $MAXRSS ]]; then 
            lmem_mb=$(percentof "$MAXRSS" "$memp" | ftoi)
            lmem=$((lmem_mb*1024*1024))
            lmemopt="-lm=${lmem} -lmp=${memp}"
        fi
        echo "Running ${cores} cores, ${thr} threads, ${NKEYS} keys"
        echo bash run.sh -c=${cores} -t=${threads} -nk=${NKEYS} ${OPTS} ${FFLAG}\
            -d="""${desc}""" -fl="""${CFLAGS}""" ${lmemopt}
        bash run.sh -c=${cores} -t=${threads} -nk=${NKEYS} ${OPTS} ${FFLAG}     \
            -d="""${desc}""" -fl="""${CFLAGS}""" ${lmemopt}
    done
}

# eden runs
rd=         # use read-ahead hints
ebs=        # set eviction batch size
evp=        # set eviction policy
evg=        # set eviction gens
tpc=1
for c in $CORES; do
    # for tpc in 1 5; do
    for rd in 0 1 3 7; do
        desc="cqsort"
        t=$((c*tpc))
        # run_vary_lmem "uthr"    "local" "$c" "$t" "$rd" "$ebs" "$evp" "$evg"
        # run_vary_lmem "pthr"    "local" "$c" "$t" "$rd" "$ebs" "$evp" "$evg"
        # run_vary_lmem "eden-nh" "local" "$c" "$t" "$rd" "$ebs" "$evp" "$evg"
        # run_vary_lmem "eden"    "local" "$c" "$t" "$rd" "$ebs" "NONE" "$evg"
        # run_vary_lmem "eden"    "local" "$c" "$t" "$rd" "8"    "NONE" "$evg"
        # run_vary_lmem "eden"    "local" "$c" "$t" "$rd" "$ebs" "SC"   "$evg"
        # run_vary_lmem "eden"    "local" "$c" "$t" "$rd" "$ebs" "LRU"  "$evg"
        # run_vary_lmem "eden-nh" "rdma"  "$c" "$t" "$rd" "$ebs" "$evp" "$evg"
        # run_vary_lmem "eden"    "rdma"  "$c" "10" "$rd" "$ebs" "NONE" "$evg"
        # run_vary_lmem "eden"    "rdma"  "$c" "50" "$rd" "$ebs" "NONE" "$evg"
        # run_vary_lmem "eden"    "rdma"  "$c" "50" "$rd" "8"    "NONE" "$evg"

        # run_vary_lmem "fswap"    "local"  "$c" "$t" "$rd" "$ebs" "$evp" "$evg"
        # run_vary_lmem "fswap"    "rdma" "$c" "$t" "$rd" "$ebs" "$evp" "$evg"
    done
done

# cleanup
rm -f ${TMP_PFX}*
rm -f __running__