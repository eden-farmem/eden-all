#!/bin/bash

#
# Fastswap
# 

usage="Example: bash run.sh -f\n
-n, --name \t optional exp name (becomes folder name)\n
-d, --readme \t optional exp description\n
-s, --setup \t rebuild and reload fastswap, farmemory server, cgroups, etc\n
-so, --setuponly \t only setup, no run\n
-c, --clean \t run only the cleanup part\n
-t, --thr \t number of kernel threads\n
-c, --cpu \t number of CPU cores\n
-m, --mem \t local memory limit for the app\n
-o, --out \t output file for any results\n
-fl,--cflags \t C flags passed to gcc when compiling the app/test\n
-d, --debug \t build debug\n
-d, --gdb \t run with a gdb server (on port :1234) to attach to\n
-h, --help \t this usage information message\n"

#Defaults
APPNAME="pfbenchmark"
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
FASTSWAP_DIR="${SCRIPT_DIR}/../../fastswap"
DATADIR="${SCRIPT_DIR}/data/"
BINFILE="${SCRIPT_DIR}/main.out"
HOST_SSH="sc40"
HOST_IP="192.168.0.40"
MEMSERVER_SSH="sc07"
MEMSERVER_IP="192.168.0.07"
MEMSERVER_PORT="50000"
FASTSWAP_RECLAIM_CPU=54     # avoid scheduling on this CPU
TMPFILE_PFX="tmp_fswap_"
RUNTIME_SECS=30
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')  #unique id
BACKEND=fastswap

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
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -fl=*|--cflags=*)
    CFLAGS="$CFLAGS ${i#*=}"
    ;;

    -s|--setup)
    SETUP=1
    ;;
        
    -so|--setuponly)
    SETUP=1
    SETUP_ONLY=1
    ;;
    
    -c|--clean)
    CLEANUP=1
    ;;

    -g|--gdb)
    GDB=1
    CFLAGS="$CFLAGS -DDEBUG -g -ggdb"
    ;;
    
    -t=*|--thr=*)
    NTHREADS="${i#*=}"
    ;;

    -c=*|--cores=*)
    NCORES="${i#*=}"
    ;;

    -m=*|--mem=*)
    LOCALMEM="${i#*=}"
    ;;

    -o=*|--out=*)
    OUTFILE=${i#*=}
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

# helpers
CFGSTORE=
save_cfg() {
    name=$1
    value=$2
    CFGSTORE="${CFGSTORE}$name:$value\n"
}
cleanup() {
    rm -f ${TMPFILE_PFX}*
    pkill sar
    rm -f *.sar
    rm -f main_pid
    sleep 1     #for ports to be unbound
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
if [[ $CLEANUP ]]; then exit 0; fi

# build & load fastswap
set -e
if [[ $SETUP ]]; then 
    bash ${FASTSWAP_DIR}/setup.sh           \
        --memserver-ssh=${MEMSERVER_SSH}    \
        --memserver-ip=${MEMSERVER_IP}      \
        --memserver-port=${MEMSERVER_PORT}  \
        --host-ip=${HOST_IP}                \
        --host-ssh=${HOST_SSH}

    if [[ $SETUP_ONLY ]]; then  exit 0; fi
fi

# build
CFLAGS="$CFLAGS -DFASTSWAP_RECLAIM_CPU=$FASTSWAP_RECLAIM_CPU"
gcc main.c utils.c -lpthread ${CFLAGS} -o ${BINFILE}

# setup localmem limit
sudo mkdir -p /cgroup2/benchmarks/$APPNAME/
LOCALMEM=${LOCALMEM:-max}
sudo bash -c "echo ${LOCALMEM} > /cgroup2/benchmarks/$APPNAME/memory.high"

# initialize run
expdir=$EXPNAME
mkdir -p $expdir
pushd $expdir
echo "running ${EXPNAME}"
save_cfg "cores"    $NCORES
save_cfg "threads"  $NTHREADS
save_cfg "warmup"   $WARMUP
save_cfg "backend"  $BACKEND
save_cfg "localmem" $LOCALMEM
save_cfg "desc"     $README
echo -e "$CFGSTORE" > settings

# start benchmark
start_sar 1

# run
wrapper="/usr/bin/time -v"
if [[ $GDB ]]; then wrapper="gdbserver :1234";   fi
sudo ${wrapper} ${BINFILE} ${NTHREADS} 2>&1 | tee app.out &
popd 
sleep 1

pid=`cat ${expdir}/main_pid`
if [[ $pid ]]; then 
    #enforce localmem
    sudo bash -c "echo $pid > /cgroup2/benchmarks/$APPNAME/cgroup.procs"
   
    # wait for finish
    while ps -p $pid > /dev/null; do sleep 1; done

    # all good, save the run
    mv ${expdir} $DATADIR/
    echo "success"
else
    echo "process failed to write pid; exiting"
fi

cleanup