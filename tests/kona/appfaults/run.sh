#!/bin/bash

#
# Test Nadav Amit's prefetch_page() API for Userfaultfd pages using Kona
# Requires this kernel patch/feature: 
# https://lore.kernel.org/lkml/20210225072910.2811795-4-namit@vmware.com/
# 

usage="Example: bash run.sh -f\n
-f, --force \t force rebuild kona\n
-kc,--kconfig \t kona build configuration (CONFIG_NO_DIRTY_TRACK/CONFIG_WP)\n
-kf,--kcflags \t C flags passed to gcc when compiling kona\n
-fl,--cflags \t C flags passed to gcc when compiling the app/test\n
-t, --threads \t number of app threads\n
-o, --out \t output file for any results\n
-s, --safemode \t build kona with safe mode on\n
-c, --clean \t run only the cleanup part\n
-d, --debug \t build debug\n
-h, --help \t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
kona_cfg="PBMEM_CONFIG=CONFIG_WP"
BINFILE="prefetch.out"
KONA_DIR="${SCRIPT_DIR}/../../../kona"
KONA_BIN="${KONA_DIR}/pbmem"
KONA_RCNTRL_SSH="sc40"
KONA_RCNTRL_IP="192.168.0.40"
KONA_RCNTRL_PORT="9202"
KONA_MEMSERVER_SSH=$KONA_RCNTRL_SSH
KONA_MEMSERVER_IP=$KONA_RCNTRL_IP
KONA_MEMSERVER_PORT="9200"

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    DEBUG="DEBUG=1"
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -fl=*|--cflags=*)
    CFLAGS="$CFLAGS ${i#*=}"
    ;;

    -kc=*|--kconfig=*)
    kona_cfg="PBMEM_CONFIG=${i#*=}"
    ;;

    -ko=*|--kcflags=*)
    kona_cflags="$kona_cflags ${i#*=}"
    ;;
    
    -af|--appfaults)
    CFLAGS="$CFLAGS -DUSE_APP_FAULTS"
    ;;

    -f|--force)
    FORCE=1
    ;;
    
    -c|--clean)
    CLEANUP=1
    ;;

    -t=*|--threads=*)
    NUM_THREADS=${i#*=}
    ;;

    -o=*|--out=*)
    OUTFILE=${i#*=}
    ;;

    -s|--safemode)
    kona_cflags="$kona_cflags -DSAFE_MODE"
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

cleanup() {
    rm -f ${BINFILE}
    ssh ${KONA_RCNTRL_SSH} "pkill rcntrl"
    ssh ${KONA_MEMSERVER_SSH} "pkill memserver"
}
if [[ $CLEANUP ]]; then
    cleanup
    exit 0
fi

set -e
# build kona
if [[ $FORCE ]]; then 
    pushd ${KONA_BIN}
    make je_clean
    make clean
    make je_jemalloc
    kona_cflags="$kona_cflags -DSERVE_APP_FAULTS"
    make all -j $kona_cfg PROVIDED_CFLAGS="""$kona_cflags""" ${DEBUG}
    popd
fi

# build
LDFLAGS="-lkona -lrdmacm -libverbs -lpthread -lstdc++ -lm -ldl -luring"
gcc main.c parse_vdso.c utils.c                 \
    -I${KONA_DIR}/liburing/src/include          \
    -I${KONA_BIN}                               \
    ${CFLAGS} ${LDFLAGS} -L${KONA_BIN} -o ${BINFILE}

set +e    #to continue to cleanup even on failure

# prepare for run
echo "Starting Kona"
# starting kona controller
scp ${KONA_BIN}/rcntrl ${KONA_RCNTRL_SSH}:~/scratch
ssh ${KONA_RCNTRL_SSH} "~/scratch/rcntrl -s $KONA_RCNTRL_IP -p $KONA_RCNTRL_PORT" &
sleep 2
# starting mem server
scp ${KONA_BIN}/memserver ${KONA_MEMSERVER_SSH}:~/scratch
ssh ${KONA_MEMSERVER_SSH} "~/scratch/memserver -s $KONA_MEMSERVER_IP -p $KONA_MEMSERVER_PORT -c $KONA_RCNTRL_IP -r $KONA_RCNTRL_PORT" &
sleep 30

# run
env="RDMA_RACK_CNTRL_IP=$KONA_RCNTRL_IP RDMA_RACK_CNTRL_PORT=$KONA_RCNTRL_PORT"
if [[ $OUTFILE ]]; then 
    sudo ${env} ./${BINFILE} ${NUM_THREADS} >> $OUTFILE
else 
    sudo ${env} ./${BINFILE} ${NUM_THREADS}
fi

# cleanup
cleanup
