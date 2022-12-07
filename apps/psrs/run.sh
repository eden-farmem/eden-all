#!/bin/bash

#
# Run sort with different threads/memory backends
# 

set -e
usage="Example: bash run.sh\n
-n, --name \t\t optional exp name (becomes folder name)\n
-d, --readme \t\t optional exp description\n
--tag \t\t optional keyword to label a set of runs\n
-f, --force \t\t force recompile everything\n
-s, --shenango \t use shenango threads\n
-e, --eden \t run with Eden's remote memory\n
-h, --hints \t enable Eden's remote memory hints\n
-fs, --fastswap \t enable remote memory with fastswap\n
-fl,--cflags \t\t C flags passed to gcc when compiling the app/test\n
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
APPNAME="psort"
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
DATADIR="${SCRIPT_DIR}/data/"
ROOT_DIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOT_DIR}/scripts/"
FASTSWAP_DIR="${ROOT_DIR}/fastswap"
BINFILE="${SCRIPT_DIR}/main.out"
RCNTRL_SSH="sc07"
RCNTRL_IP="192.168.100.81"
RCNTRL_PORT="9202"
MEMSERVER_SSH=$RCNTRL_SSH
MEMSERVER_IP=$RCNTRL_IP
MEMSERVER_PORT="9200"
SHENANGO_DIR="${ROOT_DIR}/eden"
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')  #unique id
TMP_FILE_PFX="tmp_syn_"
CFGFILE="shenango.config"

if [ "`hostname`" == "sc2-hs2-b1640" ];
then
    # fastswap
    HOST_SSH="sc40"
    HOST_IP="192.168.0.40"
    RCNTRL_IP="192.168.0.7"
    MEMSERVER_IP=$RCNTRL_IP
fi

NO_HYPERTHREADING="-noht"
EDEN=
HINTS=
BACKEND=local
EVICT_THRESHOLD=100     # no handler eviction
EVICT_BATCH_SIZE=1
EXPECTED_PTI=off
SCHEDULER=pthreads
RMEM=none
RDAHEAD=0
EVICT_GENS=1
NCORES=1
NKEYS=16000000
LMEM=1000000000    # 1GB

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

    --tag=*)
    TAG="${i#*=}"
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

    -e|--eden)
    EDEN=1
    SHENANGO=1
    ;;
    
    -h|--hints)
    EDEN=1
    HINTS=1
    SHENANGO=1
    ;;

    -fs|--fastswap)
    FASTSWAP=1
    #SHENANGO=1
    ;;

    -be=*|--batchevict=*)
    EVICT_BATCH_SIZE="${i#*=}"
    SHEN_CFLAGS="$SHEN_CFLAGS -DVECTORED_MADVISE -DVECTORED_MPROTECT"
    ;;

    -ep=*|--evictpolicy=*)
    EVICT_POLICY=${i#*=}
    ;;

    -eg=*|--evictgens=*)
    EVICT_GENS=${i#*=}
    ;;

    -se|--sampleepochs)
    SHEN_CFLAGS="$SHEN_CFLAGS -DEPOCH_SAMPLER"
    ;;

    -b=*|--bkend=*)
    BACKEND=${i#*=}
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

    -lmp=*|--lmemper=*)
    LMEMPER=${i#*=}
    ;;

    -w|--warmup)
    WARMUP=yes
    CFLAGS="$CFLAGS -DWARMUP"
    ;;

    -rd=*|--rdahead=*)
    RDAHEAD=${i#*=}
    CFLAGS="$CFLAGS -DRDAHEAD=$RDAHEAD"
    ;;

    -sf|--safemode)
    SAFEMODE=1
    ;;

    -fl=*|--cflags=*)
    CFLAGS="$CFLAGS ${i#*=}"
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
BASECORE=14
NIC_PCI_SLOT="0000:d8:00.1"
RMEM_HANDLER_CORE=55
FASTSWAP_RECLAIM_CPU=55
SHENANGO_STATS_CORE=54
SHENANGO_EXCLUDE=${SHENANGO_STATS_CORE},${FASTSWAP_RECLAIM_CPU}
NTHREADS=${NTHREADS:-$NCORES}

# helpers
start_cpu_sar() {
    int=$1
    outdir=$2
    cpustr=${3:-ALL}
    suffix=$4
    nohup sar -P ${cpustr} ${int} | ts %s > ${outdir}/cpu${suffix}.sar   2>&1 &
}
stop_sar() {
    pkill sar || true
}
start_memory_stat() {
    rm -f memory-stat.out
    nohup bash ${ROOT_SCRIPTS_DIR}/memory-stat.sh ${APPNAME} 2>&1 &
}
stop_memory_stat() {
    local pid
    pid=$(pgrep -f "[m]emory-stat.sh" || true)
    if [[ $pid ]]; then  kill ${pid}; fi
}
start_vmstat() {
    rm -f vmstat.out
    nohup bash ${ROOT_SCRIPTS_DIR}/vmstat.sh ${APPNAME} > vmstat.out &
}
stop_vmstat() {
    local pid
    pid=$(pgrep -f "[v]mstat.sh" || true)
    if [[ $pid ]]; then  kill ${pid}; fi
}
start_fsstat() {
    rm -f fstat.out
    nohup sudo bash ${ROOT_SCRIPTS_DIR}/fswap-stat.sh ${APPNAME} > fstat.out &
}
stop_fsstat() {
    local pid
    pid=$(pgrep -f "[f]swap-stat.sh" || true)
    if [[ $pid ]]; then  sudo kill ${pid}; fi
}
kill_remnants() {
    sudo pkill iokerneld || true
    ssh ${RCNTRL_SSH} "pkill rcntrl; rm -f ~/scratch/rcntrl"            # eden memcontrol
    ssh ${MEMSERVER_SSH} "pkill memserver; rm -f ~/scratch/memserver"   # eden memserver
    # ssh ${MEMSERVER_SSH} "pkill rmserver; rm -f ~/scratch/rmserver"   # fastswap server
}
cleanup() {
    if [ -z "$KEEPBIN" ]; then
        rm -f ${BINFILE}
    fi
    rm -f ${TMP_FILE_PFX}*
    kill_remnants
    stop_memory_stat
    stop_vmstat
    stop_fsstat
    stop_sar
}
cleanup     #start clean
if [[ $CLEANUP ]]; then
    exit 0
fi

# check pti state
# PTI status
PTI=on
pti_msg=$(sudo dmesg | grep 'page tables isolation: enabled' || true)
if [ -z "$pti_msg" ]; then  PTI=off; fi
if [ "$EXPECTED_PTI" != "$PTI" ]; then
    echo "Warning! Page table isolation feature is not in expected state"
    echo "Expected: ${EXPECTED_PTI}, Found: ${PTI}"
fi

# eden flags
if [[ $EDEN ]]; then
    RMEM="eden-nh"
    CFLAGS="$CFLAGS -DEDEN -DREMOTE_MEMORY"

    # hints
    if [[ $HINTS ]]; then
        RMEM="eden"
        CFLAGS="$CFLAGS -DREMOTE_MEMORY_HINTS"
    fi

    # eviction policy
    if [[ $EVICT_POLICY ]]; then
        if [[ $EVICT_POLICY != "SC" ]] && [[ $EVICT_POLICY != "LRU" ]]; then
            echo "ERROR! invalid evict policy. Allowed values: SC, LRU"
            exit 1
        fi
        # we need to set c-flags for both app and shenango cflags 
        # because eviction-specific hints are defined in a header file 
        CFLAGS="$CFLAGS -D${EVICT_POLICY}_EVICTION"
        SHEN_CFLAGS="$SHEN_CFLAGS -D${EVICT_POLICY}_EVICTION"
    fi
fi

# Fastswap
if [[ $FASTSWAP ]]; then
    RMEM="fastswap"
    CFLAGS="$CFLAGS -DFASTSWAP"

    if [[ $EDEN ]] || [[ $RHINTS ]]; then
        echo "ERROR! Eden or hints can't be enabled with fastswap"
        exit 1
    fi

    if [[ $EVICT_POLICY ]]; then
        echo "ERROR! evict policy can't be set with fastswap"
        exit 1
    fi

    # setup fastswap
    if [[ $FORCE ]]; then
        bash ${FASTSWAP_DIR}/setup.sh           \
            --memserver-ssh=${MEMSERVER_SSH}    \
            --memserver-ip=${MEMSERVER_IP}      \
            --memserver-port=${MEMSERVER_PORT}  \
            --host-ip=${HOST_IP}                \
            --host-ssh=${HOST_SSH}              \
            --backend=${BACKEND}
    fi

    # setup cgroups
    pushd ${FASTSWAP_DIR}
    sudo mkdir -p /cgroup2
    sudo ./init_bench_cgroups.sh
    sudo mkdir -p /cgroup2/benchmarks/$APPNAME/
    popd
fi

# rebuild shenango
if [[ $FORCE ]] && [[ $SHENANGO ]]; then
    pushd ${SHENANGO_DIR} 
    if [[ $FORCE ]];        then    make clean;                         fi
    if [[ $EDEN ]];         then    OPTS="$OPTS REMOTE_MEMORY=1";       fi
    if [[ $HINTS ]];        then    OPTS="$OPTS REMOTE_MEMORY_HINTS=1"; fi
    if [[ $SAFEMODE ]];     then    OPTS="$OPTS SAFEMODE=1";            fi
    if [[ $GDB ]];          then    OPTS="$OPTS GDB=1";                 fi
    if ! [[ $NO_STATS ]];   then    OPTS="$OPTS STATS_CORE=${SHENANGO_STATS_CORE}"; fi
    OPTS="$OPTS NUMA_NODE=${NUMA_NODE} EXCLUDE_CORES=${SHENANGO_EXCLUDE}"
    make all -j ${DEBUG} ${OPTS} PROVIDED_CFLAGS="""$SHEN_CFLAGS"""
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
    LIBS="${LIBS} ${SHENANGO_DIR}/libruntime.a  ${SHENANGO_DIR}/librmem.a ${SHENANGO_DIR}/libnet.a ${SHENANGO_DIR}/libbase.a -lrdmacm -libverbs"
    LDFLAGS="${LDFLAGS} -lpthread -T${SHENANGO_DIR}/base/base.ld -no-pie -lm"
fi

# compile
LIBS="${LIBS} -lpthread -lm"
gcc main.c qsort_custom.c -D_GNU_SOURCE -Wall -O ${INC} ${LIBS} ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

if [[ $BUILD_ONLY ]]; then
    exit 0
fi

# initialize run
expdir=$EXPNAME
mkdir -p $expdir

pushd $expdir
echo "running ${EXPNAME}"
save_cfg "cores"        $NCORES
save_cfg "threads"      $NTHREADS
save_cfg "keys"         $NKEYS
save_cfg "warmup"       $WARMUP
save_cfg "scheduler"    $SCHEDULER
save_cfg "rmem"         $RMEM
save_cfg "backend"      $BACKEND
save_cfg "localmem"     $LMEM
save_cfg "lmemper"      $LMEMPER
save_cfg "rdahead"      $RDAHEAD
save_cfg "evictbatch"   $EVICT_BATCH_SIZE
save_cfg "evictpolicy"  $EVICT_POLICY
save_cfg "evictgens"    $EVICT_GENS
save_cfg "desc"         $README
save_cfg "tag"          $TAG
echo -e "$CFGSTORE" > settings

# write shenango config
__RMEM_OPT=0
__HINTS_OPT=0
if [[ $EDEN ]]; then    __RMEM_OPT=1;   fi
if [[ $HINTS ]]; then   __HINTS_OPT=1;  fi
shenango_cfg="""
host_addr 192.168.0.100
host_netmask 255.255.255.0
host_gateway 192.168.0.1
runtime_kthreads ${NCORES}
runtime_guaranteed_kthreads ${NCORES}
runtime_spinning_kthreads ${NCORES}
host_mac 02:ba:dd:ca:ad:08
disable_watchdog 0
remote_memory ${__RMEM_OPT}
rmem_hints ${__HINTS_OPT}
rmem_backend ${BACKEND}
rmem_local_memory ${LMEM}
rmem_evict_threshold ${EVICT_THRESHOLD}
rmem_evict_batch_size ${EVICT_BATCH_SIZE}
rmem_evict_ngens ${EVICT_GENS}"""
echo "$shenango_cfg" > $CFGFILE
popd

# run machine setup
sudo bash ${ROOT_SCRIPTS_DIR}/machine_config.sh

# set localmem for fastswap
if [[ $FASTSWAP ]]; then
    sudo mkdir -p /cgroup2/benchmarks/$APPNAME/
    LOCALMEM=${LOCALMEM:-max}
    sudo bash -c "echo ${LMEM} > /cgroup2/benchmarks/$APPNAME/memory.high"
    # also set rdahead for fastswap
    if [[ $RDAHEAD ]]; then
        logRDAHEAD=
        case $RDAHEAD in
        "0")    logRDAHEAD=0;;
        "1")    logRDAHEAD=1;;
        "3")    logRDAHEAD=2;;
        "7")    logRDAHEAD=3;;
        "15")   logRDAHEAD=4;;
        *)      echo "unsupported rdahead"; exit;;
        esac
        echo "setting read-ahead to $logRDAHEAD pages"
        sudo sh -c "echo $logRDAHEAD > /proc/sys/vm/page-cluster"
    fi
fi

for retry in 1; do
    # prepare for run
    kill_remnants

    # prepare remote memory servers for the run
    if [[ $EDEN ]] && [ "$BACKEND" == "rdma" ]; then
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

    # env
    pushd $expdir
    if [[ $EDEN ]] && [ "$BACKEND" == "rdma" ]; then
        env="RDMA_RACK_CNTRL_IP=$RCNTRL_IP"
        env="$env RDMA_RACK_CNTRL_PORT=$RCNTRL_PORT"
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
        start_cpu_sar 1 "." ${CPUSTR}
    else 
        # pin the app to required number of cores ourselves
        # use cores 14-27 for non-hyperthreaded setting
        if [ $NCORES -gt 14 ];   then echo "WARNING! hyperthreading enabled"; fi
        CPUSTR="$BASECORE-$((BASECORE+NCORES-1))"
        wrapper="$wrapper taskset -a -c ${CPUSTR}"
        start_cpu_sar 1 "." ${CPUSTR}
    fi 

    # run in gdb server if requested
    if [[ $GDB ]]; then
        if [ -z "$wrapper" ]; then
            wrapper="gdbserver :1234 "
        else
            wrapper="gdbserver --wrapper $wrapper -- :1234 "
        fi
    fi

    # start memory stats for fastswap
    if [[ $FASTSWAP ]]; then
        start_memory_stat
        start_vmstat
        start_fsstat
        start_cpu_sar 1 "." ${FASTSWAP_RECLAIM_CPU} "_reclaim"
    fi

    # run
    args="${NKEYS} ${NTHREADS}"
    echo sudo ${wrapper} ${BINFILE} ${args} 
    nohup sudo ${wrapper} ${BINFILE} ${args} 2>&1 | tee app.out &

    # wait for run to finish
    tries=0
    while [ ! -f main_pid ] && [ $tries -lt 30 ]; do
        sleep 1
        tries=$((tries+1))
        echo "waiting for main_pid for $tries seconds"
    done
    pid=`cat main_pid`
    if [[ $pid ]]; then
        if [[ $FASTSWAP ]]; then
            #enforce localmem
            CGROUP_PROCS=/cgroup2/benchmarks/$APPNAME/cgroup.procs
            sudo bash -c "echo $pid > $CGROUP_PROCS"
            echo "added proc $(cat $CGROUP_PROCS) to cgroup"
        fi

        # wait for finish
        tries=0
        while ps -p $pid > /dev/null; do
            sleep 1
            tries=$((tries+1))
            if [[ $tries -gt 1000 ]]; then
                echo "ran too long"
                sudo kill -9 $pid
                break
            fi
        done
        popd

        # if we're here, the run has mostly succeeded
        # only retry if we have silenty failed because of rmem server
        res=$(grep "Unknown event: is server running?" ${expdir}/app.out || true)
        if [ -z "$res" ]; then 
            echo "no error; moving on"
            mv ${expdir} $DATADIR/
            echo "final results at $DATADIR/${expdir}"
            break
        fi
    else
        echo "process failed to write pid; try again or exit"
        popd
    fi
done

# cleanup
echo "final cleanup"
cleanup
