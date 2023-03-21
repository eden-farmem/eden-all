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
ROOTDIR="${SCRIPTDIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
EDENDIR="${ROOTDIR}/eden"
DATADIR="${SCRIPTDIR}/data2/"
TOOLDIR="${ROOTDIR}/fault-analysis/"
SNAPPY_DIR="${SCRIPTDIR}/snappy-c"
BINFILE="${SCRIPTDIR}/main.out"
FLAMEGRAPHDIR=~/FlameGraph/   # Local path to https://github.com/brendangregg/FlameGraph
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')
MAX_REMOTE_MEMORY_MB=16000
LMEM=$((MAX_REMOTE_MEMORY_MB*1000000))
NHANDLERS=1
CFGFILE="shenango.config"

NCORES=1
NTHREADS=1
ZIPFS="0.1"
NKEYS=1000
NBLOBS=1000

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

    # APP-SPECIFIC SETTINGS
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

# rebuild snappy
CFLAGS="$CFLAGS -g -no-pie -fno-pie"
if [[ $FORCE ]]; then 
    pushd ${SNAPPY_DIR} 
    make clean
    make PROVIDED_CFLAGS="""$CFLAGS"""
    popd
fi

# link snappy
INC="${INC} -I${SNAPPY_DIR}/"
LIBS="${LIBS} ${SNAPPY_DIR}/libsnappyc.so"

# compile
CFLAGS="$CFLAGS -DKEYS_PER_REQ=16"
CFLAGS="$CFLAGS -DCOMPRESS=5"
LIBS="${LIBS} -lpthread -lm"
gcc -O0 -g -ggdb main.c utils.c hopscotch.c zipf.c aes.c -D_GNU_SOURCE \
    ${INC} ${LIBS} ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

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
args="${CFGFILE} ${NCORES} ${NTHREADS} ${NKEYS} ${NBLOBS} ${ZIPFS}"
echo "args: ${args}"
${prefix} env ${env} ${BINFILE} ${args} 2>&1 | tee app.out

# back to app dir
popd

# post-processing
tracesfolded=${expdir}/traces/000_000.txt
if [[ $MERGE_TRACES ]]; then

    # locate the binary
    if [ ! -f ${BINFILE} ]; then 
        echo "binary not found at ${BINFILE}"
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
        -b ${BINFILE} ${procmapflag} > ${tracesfolded}
fi

if [[ $ANALYZE_TRACES ]]; then
    # Make flame graph
    APPNAME="synthetic"
    if [ ! -d ${FLAMEGRAPHDIR} ]; then 
        echo "Clone and update FLAMEGRAPHDIR to point to https://github.com/brendangregg/FlameGraph"
    fi
    python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${SCRIPTDIR} -i ${tracesfolded} -o ${expdir}/flamegraph.dat
    python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${SCRIPTDIR} -i ${tracesfolded} -z -o ${expdir}/flamegraph-zero.dat
    ${FLAMEGRAPHDIR}/flamegraph.pl ${expdir}/flamegraph.dat --title "${APPNAME}" --color=fault --width=800 > ${expdir}/flamegraph-${APPNAME}.svg
    ${FLAMEGRAPHDIR}/flamegraph.pl ${expdir}/flamegraph-zero.dat --title "${APPNAME} (Allocation Faults)" --color=fault --width=800 > ${expdir}/flamegraph-${APPNAME}-zero.svg
fi

# run succeeded
mkdir -p ${DATADIR}
mv ${expdir}/ $DATADIR/