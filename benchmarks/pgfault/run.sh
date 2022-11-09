#!/bin/bash

#
# Test Shenango's page faults 
# 

usage="Example: bash run.sh -f\n
-f, --force \t force recompile everything\n
-fl,--cflags \t C flags passed to gcc when compiling the app/test\n
-c, --cores \t number of cpu cores\n
-rm, --rmem \t run with remote memory\n
-h, --hints \t enable remote memory hints\n
-fs, --fastswap \t enable remote memory with fastswap\n
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
FASTSWAP_DIR="${ROOT_DIR}/fastswap"
APPNAME="pfbenchmark"
BINFILE="main.out"
RCNTRL_SSH="sc07"
RCNTRL_IP="192.168.100.81"
RCNTRL_PORT="9202"
MEMSERVER_SSH=$RCNTRL_SSH
MEMSERVER_IP=$RCNTRL_IP
MEMSERVER_PORT="9200"
SHENANGO_DIR="${ROOT_DIR}/eden"
TMP_FILE_PFX="tmp_shen_"
CFGFILE="default.config"
NCORES=1
OPTS=
NO_HYPERTHREADING="-noht"
SHEN_CFLAGS="-DNO_ZERO_PAGE"
RMEM_ENABLED=0
RMEM_HINTS_ENABLED=0
BACKEND=local
LOCALMEM=68719476736        # 64 GB (see RDMA_SERVER_NSLABS)
EVICT_THRESHOLD=100         # no handler eviction
EVICT_BATCH_SIZE=1
EXPECTED_PTI=off
SCHEDULER=pthreads

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

    -sc=*|--sched=*)
    SCHEDULER="${i#*=}"
    ;;

    -rm|--rmem)
    RMEM=1
    RMEM_ENABLED=1
    CFLAGS="$CFLAGS -DEDEN"
    CFLAGS="$CFLAGS -DREMOTE_MEMORY"
    SCHEDULER=shenango
    ;;
    
    -h|--hints)
    RHINTS=1
    RMEM_ENABLED=1
    RMEM_HINTS_ENABLED=1
    CFLAGS="$CFLAGS -DREMOTE_MEMORY_HINTS"
    SCHEDULER=shenango
    ;;

    -fs|--fastswap)
    FASTSWAP=1
    CFLAGS="$CFLAGS -DFASTSWAP"
    ;;

    -e|--evict)
    EVICT=1
    CFLAGS="$CFLAGS -DEVICT_ON_PATH"
    ;;

    -be=*|--batchevict=*)
    EVICT=1
    EVICT_BATCH_SIZE="${i#*=}"
    CFLAGS="$CFLAGS -DEVICT_ON_PATH"
    SHEN_CFLAGS="$SHEN_CFLAGS -DVECTORED_MADVISE -DVECTORED_MPROTECT"
    ;;

    -ep=*|--evictpolicy=*)
    EVICT_POLICY=${i#*=}
    ;;

    -b=*|--bkend=*)
    BACKEND=${i#*=}
    ;;

    -p|--preload)
    CFLAGS="$CFLAGS -DPRELOAD"
    ;;

    -f|--force)
    FORCE=1
    ;;
    
    -c|--clean)
    CLEANUP=1
    ;;

    -t=*|--threads=*)
    NCORES=${i#*=}
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
# RNIC NUMA node = 1 (good for sc30, sc40)
NUMA_NODE=1
BASECORE=14             # starting core on the node 
NIC_PCI_SLOT="0000:d8:00.1"
RMEM_HANDLER_CORE=55
FASTSWAP_RECLAIM_CPU=55
SHENANGO_STATS_CORE=54
SHENANGO_EXCLUDE=${SHENANGO_STATS_CORE},${FASTSWAP_RECLAIM_CPU}

# helpers
cleanup() {
    echo "Cleaning up..."
    rm -f ${BINFILE}
    rm -f ${TMP_FILE_PFX}*
    rm -f ${CFGFILE}
    sudo pkill ${BINFILE}
    sudo pkill iokerneld
    sudo pkill iokerneld${NO_HYPERTHREADING}
    ssh ${RCNTRL_SSH} "pkill rcntrl; rm -f ~/scratch/rcntrl" < /dev/null
    ssh ${MEMSERVER_SSH} "pkill memserver; rm -f ~/scratch/memserver" < /dev/null
    pkill sar
    rm -f *.sar
    rm -f main_pid
    sleep 1     #to unbind port
}
start_sar() {
    int=$1
    nohup sar -r ${int}     | ts %s > memory.sar  2>&1 &
    nohup sar -b ${int}     | ts %s > diskio.sar  2>&1 &
    nohup sar -P ALL ${int} | ts %s > cpu.sar     2>&1 &
    nohup sar -n DEV ${int} | ts %s > network.sar 2>&1 &
    nohup sar -B ${int}     | ts %s > pgfaults.sar 2>&1 &
}
stop_sar() {
    pkill sar
}

#start clean
cleanup
if [[ $CLEANUP ]]; then
    exit 0
fi

set -e

# check pti state
# PTI status
PTI=on
pti_msg=$(sudo dmesg | grep 'page tables isolation: enabled' || true)
if [ -z "$pti_msg" ]; then  PTI=off; fi
if [ "$EXPECTED_PTI" != "$PTI" ]; then
    echo "Warning! Page table isolation feature is not in expected state"
    echo "Expected: ${EXPECTED_PTI}, Found: ${PTI}"
fi


# setup fastswap
if [[ $FASTSWAP ]]; then
    if [[ $RMEM ]] || [[ $RHINTS ]]; then
        echo "ERROR! rmem or hints can't be enabled with fastswap"
        exit 1
    fi

    if [[ $EVICT_POLICY ]]; then
        echo "ERROR! evict policy can't be set with fastswap"
        exit 1
    fi

    if [[ $FORCE ]]; then
        bash ${FASTSWAP_DIR}/setup.sh           \
            --memserver-ssh=${MEMSERVER_SSH}    \
            --memserver-ip=${MEMSERVER_IP}      \
            --memserver-port=${MEMSERVER_PORT}  \
            --host-ip=${HOST_IP}                \
            --host-ssh=${HOST_SSH}              \
            --backend=${BACKEND}
    fi
fi

if [[ $EVICT_POLICY ]]; then
    if [[ $EVICT_POLICY != "SC" ]] && [[ $EVICT_POLICY != "LRU" ]]; then
        echo "ERROR! invalid evict policy. Allowed values: SC, LRU"
        exit 1
    fi
    SHEN_CFLAGS="$SHEN_CFLAGS -D${EVICT_POLICY}_EVICTION"
fi

# build shenango
if [ "$SCHEDULER" == "shenango" ]; then
    pushd ${SHENANGO_DIR} 
    if [[ $FORCE ]];    then    make clean;                         fi
    if [[ $RMEM ]];     then    OPTS="$OPTS REMOTE_MEMORY=1";       fi
    if [[ $RHINTS ]];   then    OPTS="$OPTS REMOTE_MEMORY_HINTS=1"; fi
    if [[ $SAFEMODE ]]; then    OPTS="$OPTS SAFEMODE=1";            fi
    if [[ $GDB ]];      then    OPTS="$OPTS GDB=1";                 fi
    if ! [[ $NO_STATS ]]; then  OPTS="$OPTS STATS_CORE=${SHENANGO_STATS_CORE}"; fi
    OPTS="$OPTS NUMA_NODE=${NUMA_NODE} EXCLUDE_CORES=${SHENANGO_EXCLUDE}"
    make all -j ${DEBUG} ${OPTS} PROVIDED_CFLAGS="""$SHEN_CFLAGS"""

    # shim
    pushd shim
    make
    popd
    popd

    INC="${INC} -I${SHENANGO_DIR}/inc"
    LDFLAGS="${LDFLAGS} -T${SHENANGO_DIR}/base/base.ld -no-pie -lm"
    LIBS="${LIBS} -Wl,--wrap=main ${SHENANGO_DIR}/shim/libshim.a -ldl"
    LIBS="${LIBS} ${SHENANGO_DIR}/libruntime.a  ${SHENANGO_DIR}/librmem.a "\
"${SHENANGO_DIR}/libnet.a ${SHENANGO_DIR}/libbase.a -lrdmacm -libverbs"
else
    LDFLAGS="${LDFLAGS} -lpthread -lm"
fi

# build benchmark
CFLAGS="$CFLAGS -DNCORES=${NCORES}"
gcc main.c utils.c -D_GNU_SOURCE ${INC} ${LDFLAGS} ${LIBS} ${CFLAGS} -o ${BINFILE}

if [[ $BUILD_ONLY ]]; then
    exit 0
fi

if [[ $LATENCIES ]] && [ $NCORES -gt 1 ]; then
    echo "can't do more than 1 thr with latency sampling"
    exit 1
fi

# prepare remote memory servers for the run
if [[ $RMEM ]] && [ "$BACKEND" == "rdma" ]; then
    echo "starting rmem servers"
    # starting controller
    scp ${SHENANGO_DIR}/rcntrl ${RCNTRL_SSH}:~/scratch
    ssh ${RCNTRL_SSH} "nohup ~/scratch/rcntrl -s $RCNTRL_IP -p $RCNTRL_PORT" < /dev/null &
    sleep 2
    # starting mem server
    scp ${SHENANGO_DIR}/memserver ${MEMSERVER_SSH}:~/scratch
    ssh ${MEMSERVER_SSH} "nohup ~/scratch/memserver -s $MEMSERVER_IP -p $MEMSERVER_PORT -c $RCNTRL_IP -r $RCNTRL_PORT" < /dev/null &
    sleep 40
fi

# low localmem to trigger evict
if [[ $EVICT ]]; then
    LOCALMEM=$((NCORES*10000000))   # 10 MB per core
fi

# fastswap setup already takes care of its memory server
# but we need to setup local mem limit in advance
if [[ $FASTSWAP ]]; then
    sudo mkdir -p /cgroup2/benchmarks/$APPNAME/
    LOCALMEM=${LOCALMEM:-max}
    sudo bash -c "echo ${LOCALMEM} > /cgroup2/benchmarks/$APPNAME/memory.high"
fi

# Core allocation
if [ "$SCHEDULER" == "shenango" ]; then
    # For Shenango, set i/o core and shenango config
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
runtime_kthreads ${NCORES}
runtime_guaranteed_kthreads ${NCORES}
runtime_spinning_kthreads ${NCORES}
host_mac 02:ba:dd:ca:ad:08
disable_watchdog 0
remote_memory ${RMEM_ENABLED}
rmem_hints ${RMEM_HINTS_ENABLED}
rmem_backend ${BACKEND}
rmem_local_memory ${LOCALMEM}
rmem_evict_threshold ${EVICT_THRESHOLD}
rmem_evict_batch_size ${EVICT_BATCH_SIZE}"""
    echo "$shenango_cfg" > $CFGFILE
    cat $CFGFILE
else
    # Pthreads
    if [ $NCORES -gt 14 ];   then echo "WARNING! hyperthreading enabled"; fi
    CPUSTR="$BASECORE-$((BASECORE+NCORES-1))"
    wrapper="taskset -a -c ${CPUSTR}"
fi


# environment
env=
if [[ $RMEM ]] && [ "$BACKEND" == "rdma" ]; then
    env="env RDMA_RACK_CNTRL_IP=$RCNTRL_IP RDMA_RACK_CNTRL_PORT=$RCNTRL_PORT"
    wrapper="$wrapper $env"
fi

if [[ $GDB ]]; then 
    prefix="gdbserver --wrapper ${wrapper} -- :1234 "
else
    # prefix="perf record -F 999"
    prefix="${wrapper}"
fi

# run
echo "running test"
if [[ $FASTSWAP ]]; then
    # Fastswap
    start_sar 1
    sudo ${prefix} ./${BINFILE} ${CFGFILE} 2>&1 &
    sleep 5     # wait for main_pid
    pid=`cat main_pid`
    if [[ $pid ]]; then
        if [[ $FASTSWAP ]]; then
            #enforce localmem
            CGROUP_PROCS=/cgroup2/benchmarks/$APPNAME/cgroup.procs
            sudo bash -c "echo $pid > $CGROUP_PROCS"
            echo "added proc $(cat $CGROUP_PROCS) to cgroup"
        fi

        # wait for finish
        while ps -p $pid > /dev/null; do sleep 1; done
        echo "done"
    else
        echo "process failed to write pid; exiting"
    fi
else
    # Eden
    sudo ${prefix} ./${BINFILE} ${CFGFILE} 2>&1
fi

# cleanup
cleanup
