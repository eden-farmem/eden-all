#!/bin/bash

#
# Test Nadav Amit's prefetch_page() API for Userfaultfd pages using Kona
# Requires this kernel patch/feature: 
# https://lore.kernel.org/lkml/20210225072910.2811795-4-namit@vmware.com/
# 

usage="Example: bash run.sh -k -f\n
-k, --kona \t\t build and attach kona to the test\n
-kc,--kona-config \t optional kona build configuration (CONFIG_NO_DIRTY_TRACK/CONFIG_WP)\n
-kf,--kona-cflags \t optional C flags passed to gcc when compiling kona\n
-f, --force \t\t force rebuild everything\n
-c, --cleanup \t\t run only the cleanup part\n
-b, --bench \t\t measure latency of prefetch page()\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
kona_cfg=CONFIG_WP
OUTFILE="prefetch.out"
KONA_DIR="${SCRIPT_DIR}/../../../kona"
KONA_BIN="${KONA_DIR}/pbmem"
KONA_RCNTRL_SSH="sc07"
KONA_RCNTRL_IP="192.168.0.7"
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
    ;;

    -k|--kona)
    KONA=1
    CFLAGS="-DWITH_KONA"
    ;;
    
    -kc=*|--kona-config=*)
    kona_cfg="PBMEM_CONFIG=${i#*=}"
    ;;

    -ko=*|--kona-cflags=*)
    kona_cflags="${i#*=}"
    ;;

    -f|--force)
    FORCE=1
    ;;
    
    -c|--cleanup)
    CLEANUP=1
    ;;
    
    -b|--bench)
    KONA=1
    CFLAGS="-DWITH_KONA"
    BENCHMARK=1
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

cleanup() {
    rm ${OUTFILE}
    if [[ $KONA ]]; then 
        ssh ${KONA_RCNTRL_SSH} "pkill rcntrl"
        ssh ${KONA_MEMSERVER_SSH} "pkill memserver"
    fi 
}
if [[ $CLEANUP ]]; then
    cleanup
    exit 0
fi

set -e
# build kona
if [[ $KONA ]] && [[ $FORCE ]]; then 
    pushd ${KONA_BIN}
    make je_clean
    make clean
    make je_jemalloc
    make all -j PBMEM_CONFIG="$kona_cfg" PROVIDED_CFLAGS=$kona_cflags ${DEBUG}
    popd
fi
``
# build
if [[ $KONA ]]; then 
    LDFLAGS="-lkona -lrdmacm -libverbs -lpthread -lstdc++ -lm -ldl -luring"
    if [[ $BENCHMARK ]]; then 
        gcc measure_prefetch_page.c parse_vdso.c \
            -I${KONA_DIR}/liburing/src/include          \
            -I${KONA_BIN}                               \
            ${CFLAGS} ${LDFLAGS} -L${KONA_BIN} -o ${OUTFILE}
    else
        gcc vdso_test_prefetch_page_kona.c parse_vdso.c \
            -I${KONA_DIR}/liburing/src/include          \
            -I${KONA_BIN}                               \
            ${CFLAGS} ${LDFLAGS} -L${KONA_BIN} -o ${OUTFILE}
    fi
else
    gcc vdso_test_prefetch_page.c parse_vdso.c  \
        ${CFLAGS} -o ${OUTFILE}
fi
set +e    #to continue to cleanup even on failure

# prepare for run
if [[ $KONA ]]; then 
    echo "Running with Kona"

    # starting kona controller
    scp ${KONA_BIN}/rcntrl ${KONA_RCNTRL_SSH}:~/scratch
    ssh ${KONA_RCNTRL_SSH} "~/scratch/rcntrl -s $KONA_RCNTRL_IP -p $KONA_RCNTRL_PORT" &
    sleep 2
    # starting mem server
    scp ${KONA_BIN}/memserver ${KONA_MEMSERVER_SSH}:~/scratch
    ssh ${KONA_MEMSERVER_SSH} "~/scratch/memserver -s $KONA_MEMSERVER_IP -p $KONA_MEMSERVER_PORT -c $KONA_RCNTRL_IP -r $KONA_RCNTRL_PORT" &
    sleep 30

    env="RDMA_RACK_CNTRL_IP=$KONA_RCNTRL_IP RDMA_RACK_CNTRL_PORT=$KONA_RCNTRL_PORT"
fi

# run
sudo ${env} ./${OUTFILE}

# cleanup
cleanup
