#!/bin/bash

#
# Test Shenango's page faults 
# 

usage="Example: bash run.sh -f\n
-f, --force \t force recompile everything\n
-wk,--with-kona \t include kona backend
-kc,--kconfig \t kona build configuration (CONFIG_NO_DIRTY_TRACK/CONFIG_WP)\n
-ko,--kopts \t C flags passed to gcc when compiling kona\n
-fl,--cflags \t C flags passed to gcc when compiling the app/test\n
-pf,--pgfaults \t build shenango with page faults feature. allowed values: SYNC, ASYNC\n
-t, --threads \t number of app threads\n
-o, --out \t output file for any results\n
-s, --safemode \t build kona with safe mode on\n
-c, --clean \t run only the cleanup part\n
-d, --debug \t build debug\n
-g, --gdb \t run with a gdb server (on port :1234) to attach to\n
-bo, --buildonly \t just recompile everything; do not run\n
-h, --help \t this usage information message\n"

# settings
SCRIPT_DIR=`dirname "$0"`
ROOT_DIR="${SCRIPT_DIR}/../.."
BINFILE="main.out"
KONA_CFG="PBMEM_CONFIG=CONFIG_WP"
KONA_OPTS="-DNO_ZEROPAGE_OPT"
KONA_DIR="${ROOT_DIR}/kona"
KONA_BIN="${KONA_DIR}/pbmem"
KONA_RCNTRL_SSH="sc40"
KONA_RCNTRL_IP="192.168.0.40"
KONA_RCNTRL_PORT="9202"
KONA_MEMSERVER_SSH=$KONA_RCNTRL_SSH
KONA_MEMSERVER_IP=$KONA_RCNTRL_IP
KONA_MEMSERVER_PORT="9200"
SHENANGO_DIR="${ROOT_DIR}/shenango"
TMP_FILE_PFX="tmp_pgf_"
CFGFILE="default.config"
NUM_THREADS=1

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

    -wk|--with-kona)
    WITH_KONA=1
    CFLAGS="$CFLAGS -DWITH_KONA"
    ;;

    -kc=*|--kconfig=*)
    KONA_CFG="PBMEM_CONFIG=${i#*=}"
    ;;

    -ko=*|--kopts=*)
    KONA_OPTS="$KONA_OPTS ${i#*=}"
    ;;
        
    -pf=*|--pgfaults=*)
    PAGE_FAULTS="${i#*=}"
    WITH_KONA=1
    CFLAGS="$CFLAGS -DWITH_KONA"
    ;;

    -sc=*|--shencfg=*)
    CFGFILE="${i#*=}"
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

    -g|--gdb)
    GDB=1
    DEBUG="DEBUG=1"
    CFLAGS="$CFLAGS -DDEBUG -g -ggdb"
    ;;

    -bo|--buildonly)
    BUILD_ONLY=1
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

# Initial CPU allocation
# NUMA node0 CPU(s):   0-13,28-41
# NUMA node1 CPU(s):   14-27,42-55
# RNIC NUMA node = 1
NUMA_NODE=1
KONA_POLLER_CORE=53
KONA_EVICTION_CORE=54
KONA_FAULT_HANDLER_CORE=55
KONA_ACCOUNTING_CORE=52
SHENANGO_EXCLUDE=${KONA_POLLER_CORE},${KONA_EVICTION_CORE},\
${KONA_FAULT_HANDLER_CORE},${KONA_ACCOUNTING_CORE}
NIC_PCI_SLOT="0000:d8:00.1"

cleanup() {
    rm -f ${BINFILE}
    rm -f ${TMP_FILE_PFX}*
    rm -f ${CFGFILE}
    sudo pkill iokerneld
    ssh ${KONA_RCNTRL_SSH} "pkill rcntrl; rm -f ~/scratch/rcntrl" 
    ssh ${KONA_MEMSERVER_SSH} "pkill memserver; rm -f ~/scratch/memserver"
}
cleanup     #start clean
if [[ $CLEANUP ]]; then
    exit 0
fi

set -e
# build kona
if [[ $FORCE ]] && [[ $WITH_KONA ]]; then 
    pushd ${KONA_BIN}
    make je_clean
    make clean
    make je_jemalloc
    KONA_OPTS="$KONA_OPTS -DSERVE_APP_FAULTS"
    make all -j $KONA_CFG PROVIDED_CFLAGS="""$KONA_OPTS""" ${DEBUG}
    popd
fi

# build shenango
if [[ $FORCE ]]; then 
    pushd ${SHENANGO_DIR} 
    make clean    
    if [[ $DPDK ]]; then    ./dpdk.sh;  fi
    if [[ $WITH_KONA ]]; then KONA_OPT="WITH_KONA=1";    fi
    if [[ $PAGE_FAULTS ]]; then PGFAULT_OPT="PAGE_FAULTS=$PAGE_FAULTS"; fi
    make all-but-tests -j ${DEBUG} ${KONA_OPT} ${PGFAULT_OPT}   \
        NUMA_NODE=${NUMA_NODE} EXCLUDE_CORES=${SHENANGO_EXCLUDE} 
    popd 
fi

# compile 
if [[ $WITH_KONA ]]; then 
    INC="${INC} -I${KONA_DIR}/liburing/src/include -I${KONA_BIN}"
    LIBS="${LIBS} -L${KONA_BIN}"
    LDFLAGS="${LDFLAGS} -lkona -lrdmacm -libverbs -lpthread -lstdc++ -lm -ldl -luring"
fi
LIBS="${LIBS} ${SHENANGO_DIR}/libruntime.a ${SHENANGO_DIR}/libnet.a ${SHENANGO_DIR}/libbase.a"
INC="${INC} -I${SHENANGO_DIR}/inc"
LDFLAGS="${LDFLAGS} -lpthread -T${SHENANGO_DIR}/base/base.ld -no-pie -lm"
gcc main.c utils.c -D_GNU_SOURCE ${INC} ${LIBS} ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

if [[ $BUILD_ONLY ]]; then 
    exit 0
fi

set +e    #to continue to cleanup even on failuer

# prepare for run
if [[ $WITH_KONA ]]; then 
    echo "starting kona servers"
    # starting kona controller
    scp ${KONA_BIN}/rcntrl ${KONA_RCNTRL_SSH}:~/scratch
    ssh ${KONA_RCNTRL_SSH} "~/scratch/rcntrl -s $KONA_RCNTRL_IP -p $KONA_RCNTRL_PORT" &
    sleep 2
    # starting mem server
    scp ${KONA_BIN}/memserver ${KONA_MEMSERVER_SSH}:~/scratch
    ssh ${KONA_MEMSERVER_SSH} "~/scratch/memserver -s $KONA_MEMSERVER_IP -p $KONA_MEMSERVER_PORT -c $KONA_RCNTRL_IP -r $KONA_RCNTRL_PORT" &
    sleep 30
fi

start_iokernel() {
    set +e
    echo "starting iokerneld"
    sudo ${SHENANGO_DIR}/scripts/setup_machine.sh || true
    binary=${SHENANGO_DIR}/iokerneld
    sudo $binary $NIC_PCI_SLOT 2>&1 | ts %s > ${TMP_FILE_PFX}iokernel.log &
    echo "waiting on iokerneld"
    sleep 5    #for iokernel to be ready
}
start_iokernel

# prepare shenango config
shenango_cfg="""
host_addr 192.168.0.100
host_netmask 255.255.255.0
host_gateway 192.168.0.1
runtime_kthreads ${NUM_THREADS}
runtime_guaranteed_kthreads ${NUM_THREADS}
runtime_spinning_kthreads 0
host_mac 02:ba:dd:ca:ad:08
disable_watchdog true"""
echo "$shenango_cfg" > $CFGFILE

# run
if [[ $GDB ]]; then gdbcmd="gdbserver :1234";   fi
env="RDMA_RACK_CNTRL_IP=$KONA_RCNTRL_IP RDMA_RACK_CNTRL_PORT=$KONA_RCNTRL_PORT"
echo "running test"
sudo ${env} ${gdbcmd} ./${BINFILE} ${CFGFILE} 2>&1 | tee $OUTFILE

# cleanup
cleanup
