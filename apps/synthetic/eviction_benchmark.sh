#!/bin/bash
# set -e

#
# Run synthetic benchmark in with various kona eviction policies
# 

usage="\n
-w, --warmup \t run warmup for a few seconds before taking measurement\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
TEMP_PFX=tmp_msyn_
PLOTSRC=${SCRIPT_DIR}/../scripts/plot.py
PLOTDIR=plots 
DATADIR=data
PLOTEXT=png
# WARMUP=1
# WFLAG="--warmup"

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

run_vary_lmem() {
    local kind=$1
    local evictp=$2
    local op=$3
    local cores=$4
    local threads=$5
    local zparams=$6

    #reset
    CFLAGS=
    OPTS=
    LS=
    CMI=

    case $kind in
    "pthr")             ;;
    "uthr")             OPTS="$OPTS --shenango";;
    "kona-pthr")        OPTS="$OPTS --with-kona";;
    "kona-uthr")        OPTS="$OPTS --shenango --with-kona";;
    "sync")             OPTS="$OPTS --shenango --with-kona --pgfaults=SYNC";;
    "async")            OPTS="$OPTS --shenango --with-kona --pgfaults=ASYNC";;
    *)                  echo "Unknown fault kind"; exit;;
    esac

    case $evictp in
    "regular")          ;;
    "lrm")              KONA_OPTS="${KONA_OPTS} -DLRM_EVICTION";;
    *)                  echo "Unknown fault kind"; exit;;
    esac

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

    # build
    bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG} -f --buildonly #--nopie   #recompile

    # run
    # for m in `seq 10 5 60`; do 
    for m in 15; do 
        check_for_stop
        name=run-$(date '+%m-%d-%H-%M-%S')
        lmem=$(echo $m | awk '{ print $1 * 1000000000/10 }')
        lmem_mb=$(echo $lmem | awk '{ print $1 /1000000 }')
        bash run.sh ${OPTS} -n=${name} -fl="""$CFLAGS""" -ko="${KONA_OPTS}"     \
                -c=${cores} -t=${threads} -nk=${NKEYS} -nb=${NBLOBS}            \
                -lm=${lmem} -zs=${zparams} -d="""${desc}"""
        xput=$(grep "result:" ${DATADIR}/$name/app.out | sed -n "s/^.*result://p")
        if [[ $xput ]]; then xputpc=$((xput/cores)); else   xputpc=;    fi
        echo "$cores,$thr,$lmem_mb,$NKEYS,$zparams,$xput,$xputpc"
    done
}

# kona runs
cores=4
for op in "zip5"; do
    for zs in 1; do 
        for tpc in 1; do
            desc="pthr"
            thr=$((cores*tpc))
            run_vary_lmem "kona-pthr" "regular" $op $cores $thr $zs
        done
    done
done

# cleanup
rm -f ${TEMP_PFX}*
rm -f __running__
