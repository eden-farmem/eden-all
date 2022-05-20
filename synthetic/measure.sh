#!/bin/bash
set -e

#
# Run synthetic benchmark in various settings
# 

usage="\n
-f, --force \t\t force re-run experiments\n
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
WARMUP=1
WFLAG="--warmup"

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -f|--force)
    FORCE=1
    ;;
    
    -w|--warmup)
    WARMUP=1
    WFLAG="--warmup"
    ;;
    
    -l|--lat)
    LATENCIES=1
    CFLAGS="$CFLAGS -DLATENCY"
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
CFLAGS_BEFORE=$CFLAGS
MAX_MOPS=50000000   
NKEYS=10000000      # 2.5 GB
NBLOBS=400000       # 3 GB
lmem=1000000000     # 1 GB
cores=1
thr=1
sample=1
zparams=0.1         # uniform

run_vary_lmem() {
    kind=$1
    op=$2
    cores=$3
    threads=$4
    zparams=$5

    #reset
    CFLAGS=
    OPTS=
    LS=
    CMI=

    case $kind in
    "vanilla")          ;;
    "kona")             OPTS="$OPTS --with-kona";;
    "apf-sync")         OPTS="$OPTS --with-kona --pgfaults=SYNC";;
    "apf-async")        OPTS="$OPTS --with-kona --pgfaults=ASYNC";;
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
    bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG} -f --buildonly   #recompile

    # run
    # for s in `seq 1 1 10`; do 
    #     zparams=$(echo $s | awk '{ printf("%.1lf", $1/10.0); }')
    for m in `seq 10 5 60`; do 
        name=run-$(date '+%m-%d-%H-%M-%S')
        lmem=$(echo $m | awk '{ print $1 * 1000000000/10 }')
        lmem_mb=$(echo $lmem | awk '{ print $1 /1000000 }')
        bash run.sh ${OPTS} -n=${name} -fl="""$CFLAGS""" ${WFLAG} ${KFLAG}                          \
                -c=${cores} -t=${threads} -nk=${NKEYS} -nb=${NBLOBS} -lm=${lmem} -zs=${zparams}     \
                -d="""${desc}"""
        xput=$(grep "result:" ${DATADIR}/$name/app.out | sed -n "s/^.*result://p")
        if [[ $xput ]]; then xputpc=$((xput/cores)); else   xputpc=;    fi
        echo "$cores,$thr,$lmem_mb,$NKEYS,$zparams,$xput,$xputpc"
    done
}

# runs
for op in "zip5" "zip50" "zip500"; do
    for zs in 1; do 
        for c in `seq 1 1 5`; do 
            desc="${op}-noht"
            t=$((c*100))
            run_vary_lmem "kona"       $op $c $t $zs 
            run_vary_lmem "apf-async"  $op $c $t $zs 
        done
    done
done

# cleanup
rm -f ${TEMP_PFX}*
