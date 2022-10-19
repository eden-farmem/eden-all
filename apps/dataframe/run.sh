#
# Run Dataframes in different settings
#

set -e
usage="bash $0 [args]\n
-n, --name \t\t optional exp name (becomes folder name)\n
-d, --readme \t\t optional exp description\n
--tag \t\t\t optional keyword to label a set of runs\n
-i, --input \t\t dataframes input\n
-c, --cores \t\t number of CPU cores (defaults to 1)\n
-t, --threads \t\t number of worker threads (defaults to --cores)\n
-k,--kona \t\t run with remote memory (kona)\n
-a,--aifm \t\t run with AIFM remote memory\n
-lm,--localmem \t local memory in bytes for kona\n
-lmp,--lmemp \t\t local memory percentage compared to app's max working set (only for logging)\n
-f, --force \t\t recompile everything\n
-d, --debug \t\t build debug and run with small inputs\n
-g, --gdb \t\t run with a gdb server (on port :1234) to attach to\n
-bo, --buildonly \t\t exit after compiling everything (no run)\n
-c, --clean \t\t run only the cleanup part\n"

# environment
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
PARSECDIR=${SCRIPT_DIR}
DATADIR="${SCRIPT_DIR}/data/"
ROOTDIR="${SCRIPT_DIR}/../../"
AIFMDIR=${ROOTDIR}/other-systems/aifm/aifm
APPDIR=${SCRIPT_DIR}/dataframe
TMPFILE_PFX="tmp_dataframes_"
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')
BINFILE=main

# default kona opts
KONA_CFG="PBMEM_CONFIG=CONFIG_WP"
KONADIR="${ROOTDIR}/backends/kona"
KONASRC="${KONADIR}/pbmem"
KONA_RCNTRL_SSH="sc40"
KONA_RCNTRL_IP="192.168.0.40"
KONA_RCNTRL_PORT="9202"
KONA_MEMSERVER_SSH=$KONA_RCNTRL_SSH
KONA_MEMSERVER_IP=$KONA_RCNTRL_IP
KONA_MEMSERVER_PORT="9200"
KONA_OPTS="-DNO_ZEROPAGE_OPT"

# benchmark
SCRATCHDIR=~/scratch
APP='dataframe'
LMEM=1000000000    # 1GB
NCORES=1
SCHEDULER=pthreads
GIT_BRANCH=master

# save settings
SETTINGS=
save_cfg() {
    name=$1
    value=$2
    SETTINGS="${SETTINGS}$name:$value\n"
}

# Read parameters
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

    -i=*|--input=*)
    INPUT="${i#*=}"
    ;;
    
    -c=*|--cores=*)
    NCORES=${i#*=}
    ;;

    -t=*|--threads=*)
    NTHREADS=${i#*=}
    ;;

    -f|--force)
    FORCE=1
    ;;

    -k|--kona)
    KONA=1
    BACKEND=kona
    GIT_BRANCH=kona
    ;;

    -a|--aifm)
    AIFM=1
    SCHEDULER=aifm
    BACKEND=aifm
    GIT_BRANCH=aifm
    BINFILE=main_tcp
    ;;

    -lm=*|--localmem=*)
    LMEM=${i#*=}
    ;;

    -lmp=*|--lmemp=*)
    LMEMP=${i#*=}
    ;;
    
    -g|--gdb)
    GDB=1
    GDBFLAG="GDB=1"
    CFLAGS="$CFLAGS -g -ggdb"
    ;;

    -d|--debug)
    DEBUG="DEBUG=1"
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -np|--nopie)
    NOPIE=1
    CFLAGS="$CFLAGS -g -no-pie -fno-pie"   #no PIE
    CXXFLAGS="$CXXFLAGS -g -no-pie -fno-pie"
    echo 0 | sudo tee /proc/sys/kernel/randomize_va_space #no ASLR
    KONA_OPTS="${KONA_OPTS} -DSAMPLE_KERNEL_FAULTS"  #turn on logging in kona
    ;;

    -bo|--buildonly)
    BUILDONLY=1
    ;;

    -c|--clean)
    CLEANUP=1
    ;;

    -*|--*)     # unknown option
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
BASECORE=14             # starting core on the node 
KONA_POLLER_CORE=53     # limit auxiliary work towards the end cores
KONA_EVICTION_CORE=54
KONA_FAULT_HANDLER_CORE=55
KONA_ACCOUNTING_CORE=52
SHENANGO_STATS_CORE=51
SHENANGO_EXCLUDE=${KONA_POLLER_CORE},${KONA_EVICTION_CORE},\
${KONA_FAULT_HANDLER_CORE},${KONA_ACCOUNTING_CORE},${SHENANGO_STATS_CORE}
NIC_PCI_SLOT="0000:d8:00.1"
NTHREADS=${NTHREADS:-$NCORES}

# cleanup
kill_remnants() {
    sudo pkill iokerneld || true
    if [[ $KONA ]]; then
        ssh ${KONA_RCNTRL_SSH} "pkill rcntrl; rm -f ~/scratch/rcntrl" 
        ssh ${KONA_MEMSERVER_SSH} "pkill memserver; rm -f ~/scratch/memserver"
    fi
    if [[ $AIFM ]]; then 
        #TODO
        echo TODO
    fi
}
cleanup() {
    if [[ $TMPFILE_PFX ]]; then  rm -f ${TMPFILE_PFX}*; fi
    kill_remnants
}
cleanup     # start clean
if [[ $CLEANUP ]]; then
    exit 0
fi

# make sure we have the right source for dataframe
pushd ${APPDIR}/
git_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$git_branch" != "$GIT_BRANCH" ]; then
    # try and switch to the right one
    git checkout ${GIT_BRANCH} || true
    git_branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$git_branch" != "$GIT_BRANCH" ]; then
        echo "ERROR! cannot switch to the source branch: ${GIT_BRANCH}"
        exit 1
    fi
fi
popd

# build kona
if [[ $FORCE ]] && [[ $KONA ]]; then
    pushd ${KONASRC}
    # make je_clean
    make clean
    make je_jemalloc
    OPTS=
    OPTS="$OPTS POLLER_CORE=$KONA_POLLER_CORE"
    OPTS="$OPTS FAULT_HANDLER_CORE=$KONA_FAULT_HANDLER_CORE"
    OPTS="$OPTS EVICTION_CORE=$KONA_EVICTION_CORE"
    OPTS="$OPTS ACCOUNTING_CORE=${KONA_ACCOUNTING_CORE}"
    if [[ $SHENANGO ]]; then    KONA_OPTS="$KONA_OPTS -DSERVE_APP_FAULTS";  fi
    make all -j $KONA_CFG $OPTS PROVIDED_CFLAGS="""$KONA_OPTS""" ${DEBUG} ${GDBFLAG}
    sudo sysctl -w vm.unprivileged_userfaultfd=1
    popd
fi

# build AIFM
CXXFLAGS=
if [[ $FORCE ]] && [[ $AIFM ]]; then
    # disable offloading in aifm
    CXXFLAGS="-DDISABLE_OFFLOAD_UNIQUE -DDISABLE_OFFLOAD_COPY_DATA_BY_IDX"
    CXXFLAGS="${CXXFLAGS} -DDISABLE_OFFLOAD_SHUFFLE_DATA_BY_IDX "
    CXXFLAGS="${CXXFLAGS} -DDISABLE_OFFLOAD_ASSIGN -DDISABLE_OFFLOAD_AGGREGATE"
    ROOTDIR_REAL=$(realpath $ROOTDIR)
    pushd ${AIFMDIR}
    make EDEN_PATH=${ROOTDIR_REAL} clean
    make CXXFLAGS="$CXXFLAGS" EDEN_PATH=${ROOTDIR_REAL} -j$(nproc)
    popd
fi

# build app
if [[ $FORCE ]]; then rm -rf ${APPDIR}/build; fi
mkdir -p ${APPDIR}/build
pushd ${APPDIR}/build
cmake -E env CXXFLAGS="$CXXFLAGS" cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=g++-9 ..
make -j$(nproc)
popd

if [[ $BUILDONLY ]]; then 
    exit 0
fi

# initialize run
expdir=$EXPNAME
mkdir -p $expdir
pushd $expdir
echo "running ${EXPNAME}"
save_cfg "cores"    $NCORES
save_cfg "threads"  $NTHREADS
save_cfg "app"      $APP
save_cfg "input"    $INPUT
save_cfg "scheduler" $SCHEDULER
save_cfg "backend"  $BACKEND
save_cfg "localmem" $LMEM
save_cfg "lmemper"  $LMEMP
save_cfg "desc"     $README
save_cfg "tag"      $TAG
echo -e "$SETTINGS" > settings

# prepare kona memory server
if [[ $KONA ]]; then
    echo "starting kona servers"
    # starting kona controller
    scp ${KONASRC}/rcntrl ${KONA_RCNTRL_SSH}:~/scratch
    ssh ${KONA_RCNTRL_SSH} "~/scratch/rcntrl -s $KONA_RCNTRL_IP -p $KONA_RCNTRL_PORT" &
    sleep 2
    # starting mem server
    scp ${KONASRC}/memserver ${KONA_MEMSERVER_SSH}:~/scratch
    ssh ${KONA_MEMSERVER_SSH} "~/scratch/memserver -s $KONA_MEMSERVER_IP -p $KONA_MEMSERVER_PORT \
        -c $KONA_RCNTRL_IP -r $KONA_RCNTRL_PORT" &
    sleep 30
fi

# run
env=
if [[ $KONA ]]; then
    env="$env LD_PRELOAD=${KONADIR}/pbmem/alloclib.so"   # requires sudo LD_PRELOAD escalation
    env="$env RDMA_RACK_CNTRL_IP=$KONA_RCNTRL_IP"
    env="$env RDMA_RACK_CNTRL_PORT=$KONA_RCNTRL_PORT"
    env="$env EVICTION_THRESHOLD=0.99"
    env="$env EVICTION_DONE_THRESHOLD=0.99"
    env="$env MEMORY_LIMIT=$LMEM"
fi
if [[ $GDB ]]; then
    echo "make sure the app was built with -g -gdb flags (added to bldconf)"
    prefix="sudo gdbserver --wrapper env ${env} -- :1234 ";
else 
    prefix="sudo env $env"
fi

if [ $NCORES -gt 14 ];   then 
    echo "WARNING! hyperthreading enabled"; 
fi
CPUSTR="$BASECORE-$((BASECORE+NCORES-1))"
taskset -a -c ${CPUSTR} ${prefix} ${APPDIR}/build/bin/${BINFILE} | tee app.out
popd

# if we're here, the run has mostly succeeded
mv ${expdir} $DATADIR/
 
# cleanup
cleanup