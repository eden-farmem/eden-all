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

# settings
NKEYS=1024000000        # 4 GB input
# LMEM=250000000        # 250 MB
LMEM=1000000000         # 1 GB
CFLAGS="$CFLAGS -DCUSTOM_QSORT"
cores=1
thr=1

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
    "pthr")             MAXRSS=7500;;
    "uthr")             MAXRSS=7500;;
    "eden-nh")          MAXRSS=7500;;
    "eden")             MAXRSS=7500;;
    "fswap")            MAXRSS=7500;;
    "fswap-uthr")       MAXRSS=7500;;
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
    for memp in `seq 20 10 100`; do
    # for memp in 50; do
        check_for_stop
        lmem_mb=$(percentof "$MAXRSS" "$memp" | ftoi)
        lmem=$((lmem_mb*1024*1024))
        echo "Running ${cores} cores, ${thr} threads, ${NKEYS} keys"
        echo bash run.sh -c=${cores} -t=${threads} -nk=${NKEYS} ${OPTS} ${FFLAG}\
            -d="""${desc}""" -fl="""${CFLAGS}""" -lm=${lmem} -lmp=${memp}
        bash run.sh -c=${cores} -t=${threads} -nk=${NKEYS} ${OPTS} ${FFLAG}     \
            -d="""${desc}""" -fl="""${CFLAGS}""" -lm=${lmem} -lmp=${memp}
    done
}

# eden runs
rd=         # use read-ahead hints
ebs=        # set eviction batch size
evp=        # set eviction policy
evg=        # set eviction gens
for c in 1; do
    for tpc in 1 5; do
    # for rd in 0 1 3 7; do
        desc="moretpc"
        # tpc=1
        t=$((c*tpc))
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
        run_vary_lmem "fswap"    "rdma" "$c" "$t" "$rd" "$ebs" "$evp" "$evg"
    done
done

# cleanup
rm -f ${TMP_PFX}*
rm -f __running__