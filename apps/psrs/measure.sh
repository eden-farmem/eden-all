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
TMP_PFX=tmp_sort
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
NKEYS=512000000         # 2 GB input
# LMEM=250000000         # 250 MB
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

desc="paper-cores"
CFLAGS_BEFORE=$CFLAGS
for cores in 8 4; do
    for lmem in 500000000; do 
        for tpc in 6 8 10 12 14; do 
            # for cfg in "pthr" "uthr" "kona-uthr" "apf-sync" "apf-async" "kona-pthr"; do
            for cfg in "kona-pthr" "apf-async+"; do
            # for cfg in "kona_pthr"; do
                OPTS=
                CFLAGS="$CFLAGS_BEFORE"
                # OPTS="$OPTS --nopie"    #no ASLR

                case $cfg in
                "pthr")             ;;
                "uthr")             OPTS="$OPTS --shenango";;
                "kona-pthr")        OPTS="$OPTS --kona --tag=pthreads";;
                "kona-uthr")        OPTS="$OPTS --shenango --kona --tag=uthreads";;
                "apf-sync")         OPTS="$OPTS --shenango --kona -pf=SYNC --tag=sync";;
                "apf-async")        OPTS="$OPTS --shenango --kona -pf=ASYNC --tag=async";;
                "apf-async+")       OPTS="$OPTS --shenango --kona -pf=ASYNC --tag=async+"; CFLAGS="$CFLAGS -DNO_QSORT_ANNOTS";;
                *)                  echo "Unknown fault kind"; exit;;
                esac
                bash run.sh ${OPTS} -fl="""${CFLAGS}""" --force --buildonly     #rebuild
                # for nkeys_ in 16 32 64 128 256 512; do
                for nkeys_ in 1024; do
                    check_for_stop
                    nkeys=$((nkeys_*1000000))
                    # lmem=$LMEM
                    thr=$((cores*tpc))
                    echo "Running ${cores} cores, ${thr} threads, ${nkeys} keys"
                    bash run.sh -c=${cores} -t=${thr} -nk=${nkeys} ${OPTS} ${FFLAG} \
                        -d="""${desc}""" -fl="""${CFLAGS}""" -lm=${lmem}
                done
            done
        done
    done
done

# cleanup
rm -f ${TMP_PFX}*
rm -f __running__