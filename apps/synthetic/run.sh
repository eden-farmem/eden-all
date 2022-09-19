#!/bin/bash

#
# Run synthetic app
# 

set -e
usage="bash run.sh
-n, --name \t optional exp name (becomes folder name)\n
-d, --readme \t optional exp description\n
-f, --force \t force recompile everything\n
-wk,--with-kona \t include kona backend
-kc,--kconfig \t kona build configuration (CONFIG_NO_DIRTY_TRACK/CONFIG_WP)\n
-ko,--kopts \t C flags passed to gcc when compiling kona\n
-fl,--cflags \t C flags passed to gcc when compiling the app/test\n
-pf,--pgfaults \t build shenango with page faults feature. allowed values: SYNC, ASYNC\n
-t, --threads \t number of shenango worker threads (defaults to --cores)\n
-c, --cores \t number of CPU cores (defaults to 1)\n
-zs, --zipfs \t S param of zipf workload\n
-nk, --nkeys \t number of keys in the hash table\n
-nb, --nblobs \t number of items in the blob array\n
-lm, --localmem \t local memory with kona (in bytes)\n
-w, --warmup \t run warmup for a few seconds before taking measurement\n
-o, --out \t output file for any results\n
-s, --safemode \t build kona with safe mode on\n
-c, --clean \t run only the cleanup part\n
-d, --debug \t build debug\n
-g, --gdb \t run with a gdb server (on port :1234) to attach to\n
-np, --nopie \t\t build without PIE/address randomization\n
-bo, --buildonly \t just recompile everything; do not run\n
-h, --help \t this usage information message\n"

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
KONA_RCNTRL_SSH="sc07"
KONA_RCNTRL_IP="192.168.0.7"
KONA_RCNTRL_PORT="9202"
KONA_MEMSERVER_SSH=$KONA_RCNTRL_SSH
KONA_MEMSERVER_IP=$KONA_RCNTRL_IP
KONA_MEMSERVER_PORT="9200"
SHENANGO_DIR="${ROOT_DIR}/scheduler"
SNAPPY_DIR="${SCRIPT_DIR}/snappy-c"
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')  #unique id
TMP_FILE_PFX="tmp_syn_"
CFGFILE="shenango.config"
NCORES=1
ZIPFS="0.1"
NKEYS=1000
NBLOBS=1000
LMEM=1000000000    # 1GB
NO_HYPERTHREADING="-noht"

# save settings
CFGSTORE=
save_cfg() {
    name=$1
    value=$2
    CFGSTORE="${CFGSTORE}$name:$value\n"
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
    NKEYS=10
    ;;

    -fl=*|--cflags=*)
    CFLAGS="$CFLAGS ${i#*=}"
    ;;

    -s|--shenango)
    SHENANGO=1
    ;;

    -wk|--with-kona)
    WITH_KONA=1
    ;;

    -kc=*|--kconfig=*)
    KONA_CFG="PBMEM_CONFIG=${i#*=}"
    ;;

    -ko=*|--kopts=*)
    KONA_OPTS="$KONA_OPTS ${i#*=}"
    ;;
        
    -pf=*|--pgfaults=*)
    PAGE_FAULTS="${i#*=}"
    SHENANGO=1
    WITH_KONA=1
    CFLAGS="$CFLAGS -DWITH_KONA -DANNOTATE_FAULTS"
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

    -zs=*|--zipfs=*)
    ZIPFS=${i#*=}
    ;;

    -nk=*|--nkeys=*)
    NKEYS=${i#*=}
    ;;

    -nb=*|--nblobs=*)
    NBLOBS=${i#*=}
    ;;

    -lm=*|--localmem=*)
    LMEM=${i#*=}
    ;;

    -w|--warmup)
    WARMUP=yes
    CFLAGS="$CFLAGS -DWARMUP"
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
BASECORE=14
KONA_POLLER_CORE=53
KONA_EVICTION_CORE=54
KONA_FAULT_HANDLER_CORE=55
KONA_ACCOUNTING_CORE=52
SHENANGO_STATS_CORE=51
SHENANGO_EXCLUDE=${KONA_POLLER_CORE},${KONA_EVICTION_CORE},\
${KONA_FAULT_HANDLER_CORE},${KONA_ACCOUNTING_CORE},${SHENANGO_STATS_CORE}
NIC_PCI_SLOT="0000:d8:00.1"
NTHREADS=${NTHREADS:-$NCORES}

# helpers
start_sar() {
    int=$1
    outdir=$2
    cpustr=${3:-ALL}
    nohup sar -P ${cpustr} ${int} | ts %s > ${outdir}/cpu.sar   2>&1 &
    # nohup sar -r ${int}     | ts %s > ${outdir}/memory.sar  2>&1 &
    # nohup sar -b ${int}     | ts %s > ${outdir}/diskio.sar  2>&1 &
    # nohup sar -n DEV ${int} | ts %s > ${outdir}/network.sar 2>&1 &
    nohup sar -B ${int}     | ts %s > ${outdir}/pgfaults.sar 2>&1 &
}
stop_sar() {
    pkill sar || true
}
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
    stop_sar
}
cleanup     #start clean
if [[ $CLEANUP ]]; then
    exit 0
fi

echo ${SCRIPT_DIR}

# build kona
if [[ $FORCE ]] && [[ $WITH_KONA ]]; then 
    pushd ${KONA_BIN}
    make clean
    OPTS=
    OPTS="$OPTS POLLER_CORE=$KONA_POLLER_CORE"
    OPTS="$OPTS FAULT_HANDLER_CORE=$KONA_FAULT_HANDLER_CORE"
    OPTS="$OPTS EVICTION_CORE=$KONA_EVICTION_CORE"
    OPTS="$OPTS ACCOUNTING_CORE=${KONA_ACCOUNTING_CORE}"
    KONA_OPTS="$KONA_OPTS -DSERVE_APP_FAULTS"
    make all -j $KONA_CFG $OPTS PROVIDED_CFLAGS="""$KONA_OPTS""" ${DEBUG}
    sudo sysctl -w vm.unprivileged_userfaultfd=1   
    echo 0 | sudo tee /proc/sys/kernel/numa_balancing   # to avoid numa hint faults 
    popd
fi

# rebuild shenango
if [[ $FORCE ]] && [[ $SHENANGO ]]; then
    pushd ${SHENANGO_DIR}
    make clean    
    if [[ $DPDK ]]; then    ./dpdk.sh;  fi
    if [[ $WITH_KONA ]]; then KONA_OPT="WITH_KONA=1";    fi
    if [[ $PAGE_FAULTS ]]; then PGFAULT_OPT="PAGE_FAULTS=$PAGE_FAULTS"; fi
    STATS_CORE_OPT="STATS_CORE=${SHENANGO_STATS_CORE}"    # for runtime stats
    make all-but-tests -j ${DEBUG} ${KONA_OPT} ${PGFAULT_OPT}       \
        NUMA_NODE=${NUMA_NODE} EXCLUDE_CORES=${SHENANGO_EXCLUDE}    \
        ${STATS_CORE_OPT}
    popd 
fi

# rebuild snappy
if [[ $FORCE ]]; then 
    pushd ${SNAPPY_DIR} 
    make clean
    make PROVIDED_CFLAGS="""$CFLAGS"""
    popd 
fi

# link kona
if [[ $WITH_KONA ]]; then 
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

# link snappy
INC="${INC} -I${SNAPPY_DIR}/"
LIBS="${LIBS} ${SNAPPY_DIR}/libsnappyc.so"

# compile
LIBS="${LIBS} -lpthread -lm"
gcc main.c utils.c hopscotch.c zipf.c aes.c -D_GNU_SOURCE \
    ${INC} ${LIBS} ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

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
save_cfg "blobs"    $NBLOBS
save_cfg "zipfs"    $ZIPFS
save_cfg "warmup"   $WARMUP
save_cfg "scheduler" $SCHEDULER
save_cfg "backend"  $BACKEND
save_cfg "localmem" $LMEM
save_cfg "pgfaults" $PAGE_FAULTS
save_cfg "desc"     $README
echo -e "$CFGSTORE" > settings

# write shenango config
shenango_cfg="""
host_addr 192.168.0.100
host_netmask 255.255.255.0
host_gateway 192.168.0.1
runtime_kthreads ${NCORES}
runtime_guaranteed_kthreads ${NCORES}
runtime_spinning_kthreads ${NCORES}
host_mac 02:ba:dd:ca:ad:08
disable_watchdog true"""
echo "$shenango_cfg" > $CFGFILE
popd

# for retry in {1..3}; do
for retry in 1; do
    # prepare for run
    kill_remnants

    # prepare kona memory server
    if [[ $WITH_KONA ]]; then 
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
            sudo $binary $NIC_PCI_SLOT 2>&1 | ts %s > ${expdir}/iokernel.log &
            echo "waiting on iokerneld"
            sleep 5    #for iokernel to be ready
        }
        start_iokernel
    fi

    # run
    pushd $expdir
    if [[ $WITH_KONA ]]; then
        env="RDMA_RACK_CNTRL_IP=$KONA_RCNTRL_IP"
        env="$env RDMA_RACK_CNTRL_PORT=$KONA_RCNTRL_PORT"
        env="$env EVICTION_THRESHOLD=0.99"
        env="$env EVICTION_DONE_THRESHOLD=0.99"
        env="$env MEMORY_LIMIT=$LMEM"
        wrapper="$wrapper $env"
    fi

    if [[ $SHENANGO ]]; then 
        # shenango takes care of scheduling but we still want 
        # to know what cores it runs to kick off sar
        # currently, iokernel takes the first core on the node 
        # and shenango provides the following cores to app
        CPUSTR="$((BASECORE+1))-$((BASECORE+NCORES))"
        start_sar 1 "." ${CPUSTR}
    else 
        # pin the app to required number of cores ourselves
        # use cores 14-27 for non-hyperthreaded setting
        if [ $NCORES -gt 14 ];   then echo "WARNING! hyperthreading enabled"; fi
        CPUSTR="$BASECORE-$((BASECORE+NCORES-1))"
        wrapper="$wrapper taskset -a -c ${CPUSTR}"
        echo "sar ${CPUSTR}"
        start_sar 1 "." ${CPUSTR}
    fi 

    if [[ $GDB ]]; then 
        wrapper="gdbserver :1234 --wrapper $wrapper --";
    fi
    args="${CFGFILE} ${NCORES} ${NTHREADS} ${NKEYS} ${NBLOBS} ${ZIPFS}"
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
echo "final cleanup"
cleanup
