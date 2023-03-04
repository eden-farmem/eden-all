#
# Run app with fltrace tool
# 

usage="bash $1 [args]\n
-n, --name \t\t optional exp name (becomes folder name)\n
-d, --readme \t\t optional exp description\n
-lm,--localmem \t\t local memory in bytes for remote memory\n
-lmp,--lmemp \t\t local memory percentage compared to app's max working set (only for logging)\n
-h, --handlers \t\t number of handler cores for the tracing tool\n
-ms, --maxsamples \t\t limit the number of samples collected per second\n
-ops, -dbops \t\t db ops\n
-f, --force \t\t force rebuild and re-run experiments\n
-d, --debug \t\t build debug\n
-sf, --safemode \t\t build in safemode\n
-g, --gdb \t\t build with symbols\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_PATH=`realpath $0`
SCRIPTDIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPTDIR}/../../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
EDENDIR="${ROOTDIR}/eden"
DATADIR="${SCRIPTDIR}/data/"
TOOLDIR="${ROOTDIR}/fault-analysis/"
FLAMEGRAPHDIR=~/FlameGraph/   # Local path to https://github.com/brendangregg/FlameGraph
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')
MAX_REMOTE_MEMORY_MB=16000
LMEM=$((MAX_REMOTE_MEMORY_MB*1000000))
NHANDLERS=1
OPS=300000
BENCH=all
SERVER_PORT=8369

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
    # METADATA
    -n=*|--name=*)
    EXPNAME="${i#*=}"
    ;;

    -d=*|--readme=*)
    README="${i#*=}"
    ;;

    # TOOL SETTINGS
    -lm=*|--localmem=*)
    LMEM=${i#*=}
    ;;

    -lmp=*|--lmemp=*)
    LMEMP=${i#*=}
    ;;

    -h=*|--handlers=*)
    NHANDLERS=${i#*=}
    ;;

    -ms=*|--maxsamples=*)
    SAMPLESPERSEC=${i#*=}
    ;;

    -m|--merge)
    MERGE_TRACES=1
    ;;

    -a|--analyze)
    ANALYZE_TRACES=1
    ;;

    # MCACHED-SPECIFIC SETTINGS
    -ops=*|--dbops=*)
    OPS=${i#*=}
    ;;

    # OTHER
    -d|--debug)
    DEBUG=1
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -f|--force)
    FORCE=1
    FFLAG="--force"
    ;;

    -sf|--safemode)
    SAFEMODE=1
    ;;

    -g|--gdb)
    GDB=1
    CFLAGS="$CFLAGS -O0 -g -ggdb"
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

# rebuild fltrace tool
if [[ $FORCE ]]; then
    pushd ${EDENDIR}
    if [[ $FORCE ]];        then    make clean;                         fi
    if [[ $SAFEMODE ]];     then    OPTS="$OPTS SAFEMODE=1";            fi
    if [[ $GDB ]];          then    OPTS="$OPTS GDB=1";                 fi
    if [[ $DEBUG ]];        then    OPTS="$OPTS DEBUG=1";               fi
    make fltrace.so -j ${DEBUG} ${OPTS}
    popd
fi

# initialize run
expdir=$EXPNAME
mkdir -p $expdir
pushd $expdir
echo "running ${EXPNAME}"

# save config
save_cfg "benchmark"        $BENCH
save_cfg "ops"              $OPS
save_cfg "localmem"         $LMEM
save_cfg "localmempercent"  $LMEMP
save_cfg "handlers"         $NHANDLERS
save_cfg "samples"          $SAMPLESPERSEC
save_cfg "desc"             $README
echo -e "$SETTINGS" > settings

# tool parameters
env="$env LD_PRELOAD=${EDENDIR}/fltrace.so"
env="$env FLTRACE_LOCAL_MEMORY_MB=$((LMEM/1000000))"
env="$env FLTRACE_MAX_MEMORY_MB=${MAX_REMOTE_MEMORY_MB}"
env="$env FLTRACE_NHANDLERS=${NHANDLERS}"
if [[ $SAMPLESPERSEC ]]; then 
    env="$env FLTRACE_MAX_SAMPLES_PER_SEC=$SAMPLESPERSEC"
fi

# run app with tool
prefix="time -p"
if [[ $GDB ]]; then  prefix="gdb --args";   fi

# run app
pkill memcached
${prefix} env ${env} ${SCRIPTDIR}/memcached/memcached -p $SERVER_PORT -u nobody -t 10  \
    -m 4096000000 2>&1 | tee server.out &
# memcached -p 7000 -u nobody
sleep 5

# run client
MC_BENCH_FLAGS=(
    '-h 127.0.0.1'
    "-p $SERVER_PORT"
    "-n ${OPS}"
    '-c 50'
    '-d 500'
    '-r 1000000'
)
${SCRIPTDIR}/mc-benchmark/mc-benchmark ${MC_BENCH_FLAGS[@]} 2>&1 | tee client.out

# kill server
pkill memcached

# back to app dir
popd

# post-processing
tracesfolded=${expdir}/traces/000_000.txt
if [[ $MERGE_TRACES ]]; then

    # locate the binary
    binfile=${SCRIPTDIR}/memcached/memcached
    if [ ! -f ${binfile} ]; then 
        echo "binary not found at ${binpath}"
        exit 1
    fi

    # locate fault samples data
    faultsin=$(ls ${expdir}/fault-samples-*.out | head -1)
    if [ ! -f ${faultsin} ]; then 
        echo "no fault-samples-*.out found for ${APP} at ${expdir}"
        exit 1
    fi

    #locate procmaps file
    procmapflag=
    procmaps=$(ls ${expdir}/procmaps-* 2>/dev/null | head -1)
    if [ -f ${procmaps} ]; then 
        procmapflag="-pm ${procmaps}"
    fi

    mkdir -p ${expdir}/traces
    if [ -f ${tracesfolded} ]; then
        echo "traces already exist for ${APP} at ${expdir}"
        continue
    fi

    # merge traces
    allfaultsin=$(ls ${expdir}/fault-samples-*.out)
    python3 ${ROOT_SCRIPTS_DIR}/parse_fltrace_samples.py -i ${allfaultsin}    \
        -b ${binfile} ${procmapflag} > ${tracesfolded}
fi

if [[ $ANALYZE_TRACES ]]; then
    # Make flame graph
    APPNAME="memcached"
    if [ ! -d ${FLAMEGRAPHDIR} ]; then 
        echo "Clone and update FLAMEGRAPHDIR to point to https://github.com/brendangregg/FlameGraph"
    fi
    python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${SCRIPTDIR}/${APPNAME} -i ${tracesfolded} -o ${expdir}/flamegraph.dat
    python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${SCRIPTDIR}/${APPNAME} -i ${tracesfolded} -z -o ${expdir}/flamegraph-zero.dat
    ${FLAMEGRAPHDIR}/flamegraph.pl ${expdir}/flamegraph.dat --title "${APPNAME}" --color=fault > ${expdir}/flamegraph-${APPNAME}.svg
    ${FLAMEGRAPHDIR}/flamegraph.pl ${expdir}/flamegraph-zero.dat --title "${APPNAME} (Allocation Faults)" --color=fault > ${expdir}/flamegraph-${APPNAME}-zero.svg
fi

# run succeeded
mkdir -p ${DATADIR}
mv ${expdir}/ $DATADIR/