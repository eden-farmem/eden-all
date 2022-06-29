#!/bin/bash

#
# Run sort with different threads/memory backends
# 

set -e
usage="Example: bash run.sh\n
-n, --name \t\t optional exp name (becomes folder name)\n
-d, --readme \t\t optional exp description\n
-f, --force \t\t force recompile everything\n
-s, --shenango \t use shenango threads\n
-k,--kona \t\t run with remote memory (kona)\n
-kc,--kconfig \t\t kona build configuration (CONFIG_NO_DIRTY_TRACK/CONFIG_WP)\n
-ko,--kopts \t\t C flags passed to gcc when compiling kona\n
-fl,--cflags \t\t C flags passed to gcc when compiling the app/test\n
-pf,--pgfaults \t build shenango with page faults feature. allowed values: SYNC, ASYNC\n
-c, --cores \t\t number of CPU cores (defaults to 1)\n
-t, --threads \t\t number of worker threads (defaults to --cores)\n
-nk, --nkeys \t\t number of keys to sort\n
-lm, --localmem \t local memory with kona (in bytes)\n
-w, --warmup \t\t run warmup for a few seconds before taking measurement\n
-o, --out \t\t output file for any results\n
-s, --safemode \t build kona with safe mode on\n
-c, --clean \t\t run only the cleanup part\n
-d, --debug \t\t build debug\n
-g, --gdb \t\t run with a gdb server (on port :1234) to attach to\n
-np, --nopie \t\t build without PIE/address randomization\n
-bo, --buildonly \t just recompile everything; do not run\n
-h, --help \t\t this usage information message\n"

# settings
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
DATADIR="${SCRIPT_DIR}/data/"
ROOT_DIR="${SCRIPT_DIR}/../../"
BINFILE="${SCRIPT_DIR}/main.out"
KONA_CFG="PBMEM_CONFIG=CONFIG_WP"
KONA_OPTS="-DNO_ZEROPAGE_OPT"
KONA_DIR="${ROOT_DIR}/backends/kona"
KONA_BIN="${KONA_DIR}/pbmem"
KONA_RCNTRL_SSH="sc40"
KONA_RCNTRL_IP="192.168.0.40"
KONA_RCNTRL_PORT="9202"
KONA_MEMSERVER_SSH=$KONA_RCNTRL_SSH
KONA_MEMSERVER_IP=$KONA_RCNTRL_IP
KONA_MEMSERVER_PORT="9200"
SHENANGO_DIR="${ROOT_DIR}/scheduler"
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')  #unique id
TMP_FILE_PFX="tmp_syn_"
CFGFILE="shenango.config"
NCORES=1
NKEYS=16000000
LMEM=1000000000    # 1GB
NO_HYPERTHREADING="-noht"
README="notset"

# save settings
SETTINGS=
save_cfg() {
    name=$1
    value=$2
    SETTINGS="${SETTINGS}$name:$value\n"
}

# parse cli
for i in "$@"
do
case $i in
    -n=*|--name=*)
    EXPNAME="${i#*=}"
    ;;

    -d=*|--readme=*)
    README="${i#*=}"
    ;;

    -d|--debug)
    DEBUG="DEBUG=1"
    CFLAGS="$CFLAGS -DDEBUG"
    NKEYS=1000
    LMEM=200000000    # 200MB
    ;;

    -s|--shenango)
    SHENANGO=1
    ;;

    -k|--kona)
    KONA=1
    ;;

    -kc=*|--kconfig=*)
    KONA_CFG="PBMEM_CONFIG=${i#*=}"
    ;;

    -ko=*|--kopts=*)
    KONA_OPTS="$KONA_OPTS ${i#*=}"
    ;;
        
    -pf=*|--pgfaults=*)
    SHENANGO=1  #only supported on shenango
    KONA=1
    PAGE_FAULTS="${i#*=}"
    CFLAGS="$CFLAGS -DANNOTATE_FAULTS"
    CFLAGS="$CFLAGS -DPAGE_FAULTS_${i#*=}"
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

    -c=*|--cores=*)
    NCORES=${i#*=}
    ;;

    -t=*|--threads=*)
    NTHREADS=${i#*=}
    ;;

    -nk=*|--nkeys=*)
    NKEYS=${i#*=}
    ;;

    -lm=*|--localmem=*)
    LMEM=${i#*=}
    ;;

    -w|--warmup)
    WARMUP=yes
    CFLAGS="$CFLAGS -DWARMUP"
    ;;

    -s|--safemode)
    kona_cflags="$kona_cflags -DSAFE_MODE"
    ;;

    -fl=*|--cflags=*)
    CFLAGS="$CFLAGS ${i#*=}"
    ;;

    -g|--gdb)
    GDB=1
    DEBUG="DEBUG=1"
    CFLAGS="$CFLAGS -DDEBUG -g -ggdb"
    ;;

    -np|--nopie)
    KEEPBIN=1
    CFLAGS="$CFLAGS -g"                 #for symbols
    CFLAGS="$CFLAGS -no-pie -fno-pie"   #no PIE
    echo 0 | sudo tee /proc/sys/kernel/randomize_va_space #no ASLR
    KONA_OPTS="$KONA_OPTS -DSAMPLE_KERNEL_FAULTS"  #turn on logging in kona
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
SHENANGO_STATS_CORE=51
SHENANGO_EXCLUDE=${KONA_POLLER_CORE},${KONA_EVICTION_CORE},\
${KONA_FAULT_HANDLER_CORE},${KONA_ACCOUNTING_CORE},${SHENANGO_STATS_CORE}
NIC_PCI_SLOT="0000:d8:00.1"
NTHREADS=${NTHREADS:-$NCORES}

kill_remnants() {
    sudo pkill iokerneld || true
    ssh ${KONA_RCNTRL_SSH} "pkill rcntrl; rm -f ~/scratch/rcntrl" 
    ssh ${KONA_MEMSERVER_SSH} "pkill memserver; rm -f ~/scratch/memserver"
}
cleanup() {
    if [ -z "$KEEPBIN" ]; then
        rm -f ${BINFILE}
    fi
    rm -f ${TMP_FILE_PFX}*
    kill_remnants
}
cleanup     #start clean
if [[ $CLEANUP ]]; then
    exit 0
fi

echo ${SCRIPT_DIR}

# build kona
if [[ $FORCE ]] && [[ $KONA ]]; then
    pushd ${KONA_BIN}
    # make je_clean
    make clean
    make je_jemalloc
    OPTS=
    OPTS="$OPTS POLLER_CORE=$KONA_POLLER_CORE"
    OPTS="$OPTS FAULT_HANDLER_CORE=$KONA_FAULT_HANDLER_CORE"
    OPTS="$OPTS EVICTION_CORE=$KONA_EVICTION_CORE"
    OPTS="$OPTS ACCOUNTING_CORE=${KONA_ACCOUNTING_CORE}"
    if [[ $SHENANGO ]]; then    KONA_OPTS="$KONA_OPTS -DSERVE_APP_FAULTS";  fi
    make all -j $KONA_CFG $OPTS PROVIDED_CFLAGS="""$KONA_OPTS""" ${DEBUG}
    sudo sysctl -w vm.unprivileged_userfaultfd=1    
    popd
fi

# rebuild shenango
if [[ $FORCE ]] && [[ $SHENANGO ]]; then
    pushd ${SHENANGO_DIR} 
    make clean    
    if [[ $DPDK ]]; then    ./dpdk.sh;  fi
    if [[ $KONA ]]; then KONA_OPT="WITH_KONA=1";    fi
    if [[ $PAGE_FAULTS ]]; then PGFAULT_OPT="PAGE_FAULTS=$PAGE_FAULTS"; fi
    STATS_CORE_OPT="STATS_CORE=${SHENANGO_STATS_CORE}"    # for runtime stats
    make all-but-tests -j ${DEBUG} ${KONA_OPT} ${PGFAULT_OPT}       \
        NUMA_NODE=${NUMA_NODE} EXCLUDE_CORES=${SHENANGO_EXCLUDE}    \
        ${STATS_CORE_OPT}
    popd 
fi

# link kona
if [[ $KONA ]]; then
    BACKEND="kona"
	CFLAGS="${CFLAGS} -DWITH_KONA"
    INC="${INC} -I${KONA_DIR}/liburing/src/include -I${KONA_BIN}"
    LIBS="${LIBS} -L${KONA_BIN}"
    LDFLAGS="${LDFLAGS} -lkona -lrdmacm -libverbs -lpthread -lstdc++ -lm -ldl -luring"
fi

# link shenango
if [[ $SHENANGO ]]; then
	SCHEDULER="shenango"
	CFLAGS="${CFLAGS} -DSHENANGO"
    INC="${INC} -I${SHENANGO_DIR}/inc"
    LIBS="${LIBS} ${SHENANGO_DIR}/libruntime.a ${SHENANGO_DIR}/libnet.a ${SHENANGO_DIR}/libbase.a"
    LDFLAGS="${LDFLAGS} -lpthread -T${SHENANGO_DIR}/base/base.ld -no-pie -lm"
fi

# compile
gcc main.c qsort_custom.c -lpthread -D_GNU_SOURCE -Wall -O ${INC} ${LIBS} ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

if [[ $BUILD_ONLY ]]; then
    exit 0
fi

# initialize run
expdir=$EXPNAME
mkdir -p $expdir
pushd $expdir
echo "running ${EXPNAME}"
save_cfg "cores"    $NCORES
save_cfg "threads"  $NTHREADS
save_cfg "keys"     $NKEYS
save_cfg "warmup"   $WARMUP
save_cfg "scheduler" $SCHEDULER
save_cfg "backend"  $BACKEND
save_cfg "localmem" $LMEM
save_cfg "pgfaults" $PAGE_FAULTS
save_cfg "desc"     $README
echo -e "$SETTINGS" > settings

# prepare shenango config
if [[ $SHENANGO ]]; then
    shenango_cfg="""
host_addr 192.168.0.100
host_netmask 255.255.255.0
host_gateway 192.168.0.1
runtime_kthreads ${NCORES}
runtime_guaranteed_kthreads ${NCORES}
runtime_spinning_kthreads 0
host_mac 02:ba:dd:ca:ad:08
disable_watchdog true"""
    echo "$shenango_cfg" > $CFGFILE
fi
popd

for retry in 1; do
    kill_remnants

    # prepare kona memory server
    if [[ $KONA ]]; then
        echo "starting kona servers"
        # starting kona controller
        scp ${KONA_BIN}/rcntrl ${KONA_RCNTRL_SSH}:~/scratch
        ssh ${KONA_RCNTRL_SSH} "~/scratch/rcntrl -s $KONA_RCNTRL_IP -p $KONA_RCNTRL_PORT" &
        sleep 2
        # starting mem server
        scp ${KONA_BIN}/memserver ${KONA_MEMSERVER_SSH}:~/scratch
        ssh ${KONA_MEMSERVER_SSH} "~/scratch/memserver -s $KONA_MEMSERVER_IP -p $KONA_MEMSERVER_PORT \
            -c $KONA_RCNTRL_IP -r $KONA_RCNTRL_PORT" &
        sleep 30
    fi

    # setup shenango runtime
    if [[ $SHENANGO ]]; then
        start_iokernel() {
            echo "starting iokerneld"
            sudo ${SHENANGO_DIR}/scripts/setup_machine.sh || true
            binary=${SHENANGO_DIR}/iokerneld${NO_HYPERTHREADING}
            sudo $binary $NIC_PCI_SLOT 2>&1 | ts %s > iokernel.log &
            echo "waiting on iokerneld"
            sleep 5    #for iokernel to be ready
        }
        start_iokernel
    fi

    # run
    pushd $expdir
    if [[ $KONA ]]; then
        env="RDMA_RACK_CNTRL_IP=$KONA_RCNTRL_IP"
        env="$env RDMA_RACK_CNTRL_PORT=$KONA_RCNTRL_PORT"
        env="$env EVICTION_THRESHOLD=0.99"
        env="$env EVICTION_DONE_THRESHOLD=0.99"
        env="$env MEMORY_LIMIT=$LMEM"
        wrapper="$wrapper $env"
    fi
    if ! [[ $SHENANGO ]]; then 
        # use cores 14-27 for non-hyperthreaded setting
        if [ $NCORES -gt 14 ];   then echo "WARNING! hyperthreading enabled"; fi
        BASECORE=14
        CPUSTR="$BASECORE-$((BASECORE+NCORES-1))"
        wrapper="$wrapper taskset -a -c ${CPUSTR}"
    fi
    if [[ $GDB ]]; then 
        wrapper="gdbserver :1234 --wrapper $wrapper --";
    fi
    # args="${CFGFILE} ${NCORES} ${NTHREADS} ${NKEYS}"	#shenango args
    args="${NKEYS} ${NTHREADS}"
    echo sudo ${wrapper} ${gdbcmd} ${BINFILE} ${args}
    sudo ${wrapper} ${gdbcmd} ${BINFILE} ${args} 2>&1 | tee app.out
    popd

    # if we're here, the run has mostly succeeded
    # only retry if we have silenty failed because of kona server
    res=$(grep "Unknown event: is server running?" ${expdir}/app.out || true)
    if [ -z "$res" ]; then 
        echo "no error; moving on"
        mv ${expdir} $DATADIR/
        break
    fi
done

# cleanup
cleanup
