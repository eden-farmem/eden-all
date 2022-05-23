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
TEMP_PFX=tmp_msyn_
WARMUP=1

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
NKEYS=16000000      # ? GB
lmem=1000000000     # 1 GB
cores=1
thr=1

# run_vary_lmem() {
#     kind=$1
#     op=$2
#     cores=$3
#     threads=$4

#     #reset
#     CFLAGS=
#     OPTS=
#     LS=
#     CMI=

#     case $kind in
#     "kthreads")       	;;
#     "uthreads")       	OPTS="$OPTS --shenango";;
#     "kona")             OPTS="$OPTS --kona";;
#     "apf-sync")         OPTS="$OPTS --kona --pgfaults=SYNC";;
#     "apf-async")        OPTS="$OPTS --kona --pgfaults=ASYNC";;
#     *)                  echo "Unknown fault kind"; exit;;
#     esac

#     # build
#     bash run.sh ${OPTS} -fl="""$CFLAGS""" ${WFLAG} -f --buildonly   #recompile

#     # run
#     # for s in `seq 1 1 10`; do 
#     #     zparams=$(echo $s | awk '{ printf("%.1lf", $1/10.0); }')
#     for m in `seq 10 5 60`; do 
#         name=run-$(date '+%m-%d-%H-%M-%S')
#         lmem=$(echo $m | awk '{ print $1 * 1000000000/10 }')
#         lmem_mb=$(echo $lmem | awk '{ print $1 /1000000 }')
#         bash run.sh ${OPTS} -n=${name} -fl="""$CFLAGS""" ${WFLAG} ${KFLAG}	 	\
#                 -c=${cores} -t=${threads} -nk=${NKEYS} -lm=${lmem} -d="""${desc}"""
#     done
# }

# cleanup
rm -f ${TEMP_PFX}*


for nkeys_ in 16 32 64 128 256 512 1024 2048 4096; do 
# for nkeys in 16; do 
	nkeys=$((nkeys_*1000000))
	for cores in 2 4 6 8 10 12; do
		echo "Running ${cores} cores, ${nkeys} keys"
		thr=$cores
		desc="baseline"
		bash run.sh -c=${cores} -t=${thr} -nk=${nkeys} -d="""${desc}"""
	done
done
