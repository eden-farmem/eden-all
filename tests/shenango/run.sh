#!/bin/bash

#
# Test Shenango's page faults 
# 

usage="Example: bash run.sh -f\n
-f, --force \t force recompile everything\n
-fl,--cflags \t C flags passed to gcc when compiling the app/test\n
-t, --threads \t number of app threads\n
-rm, --rmem \t run with remote memory\n
-h, --hints \t enable remote memory hints\n
-o, --out \t output file for any results\n
-s, --safe \t keep the assert statements during compile\n
-c, --clean \t run only the cleanup part\n
-d, --debug \t build debug\n
-g, --gdb \t run with a gdb server (on port :1234) to attach to\n
-bo, --buildonly \t just recompile everything; do not run\n
-h, --help \t this usage information message\n"

# settings
SCRIPT_DIR=`dirname "$0"`
ROOT_DIR="${SCRIPT_DIR}/../.."
BINFILE="main.out"
RCNTRL_SSH="sc07"
RCNTRL_IP="192.168.0.7"
RCNTRL_PORT="9202"
MEMSERVER_SSH=$RCNTRL_SSH
MEMSERVER_IP=$RCNTRL_IP
MEMSERVER_PORT="9200"
SHENANGO_DIR="${ROOT_DIR}/scheduler"
TMP_FILE_PFX="tmp_shen_"
CFGFILE="default.config"
NUM_THREADS=1
OPTS=
NO_HYPERTHREADING="-noht"
SHEN_CFLAGS="-DNO_ZERO_PAGE"
RMEM_ENABLED=0
RMEM_HINTS_ENABLED=0
BACKEND=local
LOCALMEM=68719476736        # 64 GB (see RDMA_SERVER_NSLABS)

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

    -sc=*|--shencfg=*)
    CFGFILE="${i#*=}"
    ;;

    -rm|--rmem)
    RMEM=1
    RMEM_ENABLED=1
    CFLAGS="$CFLAGS -DREMOTE_MEMORY"
    ;;
    
    -h|--hints)
    RHINTS=1
    RMEM_ENABLED=1
    RMEM_HINTS_ENABLED=1
    CFLAGS="$CFLAGS -DREMOTE_MEMORY_HINTS"
    ;;

    -e|--evict)
    LOCALMEM=100000000    # 100MB to trigger eviction on most faults
    ;;

    -b=*|--bkend=*)
    BACKEND=${i#*=}
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
    
    -l|--lat)
    LATENCIES=1
    CFLAGS="$CFLAGS -DLATENCY"
    ;;

    -rd=*|--rdahead=*)
    RDAHEAD=${i#*=}
    CFLAGS="$CFLAGS -DRDAHEAD=${RDAHEAD}"
    ;;

    -o=*|--out=*)
    OUTFILE=${i#*=}
    ;;
    
    -s|--safe)
    SAFEMODE=1
    ;;

    -g|--gdb)
    GDB=1
    CFLAGS="$CFLAGS -g -ggdb"
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
NIC_PCI_SLOT="0000:d8:00.1"
RMEM_HANDLER_CORE=55
SHENANGO_STATS_CORE=46
SHENANGO_EXCLUDE=${SHENANGO_STATS_CORE}

cleanup() {
    echo "Cleaning up..."
    rm -f ${BINFILE}
    rm -f ${TMP_FILE_PFX}*
    rm -f ${CFGFILE}
    sudo pkill iokerneld
    sudo pkill iokerneld${NO_HYPERTHREADING}
    ssh ${RCNTRL_SSH} "pkill rcntrl; rm -f ~/scratch/rcntrl" 
    ssh ${MEMSERVER_SSH} "pkill memserver; rm -f ~/scratch/memserver"
}
cleanup     #start clean
if [[ $CLEANUP ]]; then
    exit 0
fi

set -e

# build shenango
pushd ${SHENANGO_DIR} 
if [[ $FORCE ]];    then    make clean;                         fi
if [[ $DPDK ]];     then    ./dpdk.sh;                          fi
if [[ $RMEM ]];     then    OPTS="$OPTS REMOTE_MEMORY=1";       fi
if [[ $RHINTS ]];   then    OPTS="$OPTS REMOTE_MEMORY_HINTS=1"; fi
if [[ $SAFEMODE ]]; then    OPTS="$OPTS SAFEMODE=1";            fi
if [[ $GDB ]];      then    OPTS="$OPTS GDB=1";                 fi
if ! [[ $NO_STATS ]]; then  OPTS="$OPTS STATS_CORE=${SHENANGO_STATS_CORE}"; fi

# NOTE: make "-j" was causing iokernel issues when compiling with gcc -O3 flag
OPTS="$OPTS NUMA_NODE=${NUMA_NODE} EXCLUDE_CORES=${SHENANGO_EXCLUDE}"
make runtime -j ${DEBUG} ${OPTS} ${SAFEMODE_OPT} PROVIDED_CFLAGS="""$SHEN_CFLAGS"""
make iok -j ${DEBUG} ${OPTS} ${SAFEMODE_OPT} PROVIDED_CFLAGS="""$SHEN_CFLAGS"""
popd

LIBS="${LIBS} ${SHENANGO_DIR}/libruntime.a  ${SHENANGO_DIR}/librmem.a "\
"${SHENANGO_DIR}/libnet.a ${SHENANGO_DIR}/libbase.a -lrdmacm -libverbs"
INC="${INC} -I${SHENANGO_DIR}/inc"
LDFLAGS="${LDFLAGS} -lpthread -T${SHENANGO_DIR}/base/base.ld -no-pie -lm"
gcc main.c utils.c -D_GNU_SOURCE ${INC} ${LIBS} ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

if [[ $BUILD_ONLY ]]; then 
    exit 0
fi

if [[ $LATENCIES ]] && [ $NUM_THREADS -gt 1 ]; then
    echo "can't do more than 1 thr with latency sampling"
    exit 1
fi

# prepare remote memory servers for the run
if [[ $RMEM ]] && [ "$BACKEND" == "rdma" ]; then
    echo "starting rmem servers"
    # starting controller
    scp ${SHENANGO_DIR}/rcntrl ${RCNTRL_SSH}:~/scratch
    ssh ${RCNTRL_SSH} "nohup ~/scratch/rcntrl -s $RCNTRL_IP -p $RCNTRL_PORT" &
    sleep 2
    # starting mem server
    scp ${SHENANGO_DIR}/memserver ${MEMSERVER_SSH}:~/scratch
    ssh ${MEMSERVER_SSH} "nohup ~/scratch/memserver -s $MEMSERVER_IP -p $MEMSERVER_PORT -c $RCNTRL_IP -r $RCNTRL_PORT" &
    sleep 40
fi

start_iokernel() {
    set +e
    echo "starting iokerneld"
    sudo ${SHENANGO_DIR}/scripts/setup_machine.sh || true
    binary=${SHENANGO_DIR}/iokerneld${NO_HYPERTHREADING}
    sudo $binary $NIC_PCI_SLOT 2>&1 | ts %s > ${TMP_FILE_PFX}iokernel.log &
    echo "waiting on iokerneld"
    sleep 10    #for iokernel to be ready
}
start_iokernel

# prepare shenango config
shenango_cfg="""
host_addr 192.168.0.100
host_netmask 255.255.255.0
host_gateway 192.168.0.1
runtime_kthreads ${NUM_THREADS}
runtime_guaranteed_kthreads ${NUM_THREADS}
runtime_spinning_kthreads ${NUM_THREADS}
host_mac 02:ba:dd:ca:ad:08
disable_watchdog true
remote_memory ${RMEM_ENABLED}
rmem_hints ${RMEM_HINTS_ENABLED}
rmem_backend ${BACKEND}
rmem_local_memory ${LOCALMEM}"""
echo "$shenango_cfg" > $CFGFILE
cat $CFGFILE

# run
env=
if [ "$BACKEND" == "rdma" ]; then
    env="RDMA_RACK_CNTRL_IP=$RCNTRL_IP RDMA_RACK_CNTRL_PORT=$RCNTRL_PORT"
fi
if [[ $GDB ]]; then 
    prefix="gdbserver --wrapper env ${env} -- :1234 "
else
    # prefix="env ${env} perf record -F 999 "
    prefix="env ${env}"
fi
echo "running test"
if [[ $OUTFILE ]]; then
    sudo ${prefix} ./${BINFILE} ${CFGFILE} | tee -a $OUTFILE
else
    sudo ${prefix} ./${BINFILE} ${CFGFILE}
fi

# cleanup
# cleanup
