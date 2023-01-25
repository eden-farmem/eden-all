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
-ops, --dbops \t\t number of db ops\n
-b, --bench \t\t db benchmark to run\n
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
APPDIR="${SCRIPTDIR}/leveldb/"
TOOLDIR="${ROOTDIR}/fault-analysis/"
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')
MAX_REMOTE_MEMORY_MB=16000
LMEM=$((MAX_REMOTE_MEMORY_MB*1000000))
NHANDLERS=1
OPS=300000
BENCH=all

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

    # LEVELDB-SPECIFIC SETTINGS
    -ops=*|--dbops=*)
    OPS=${i#*=}
    ;;

    -b=*|--bench=*)
    BENCH=${i#*=}
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

# figure out benchmark
benchmark=
case $BENCH in
"all")              benchmark="fillrandom,readseq,readrandom,readreverse,seekrandom,deleteseq,deleterandom,stats";;
"readseq")          benchmark="fillseq,fillrandom,readseq,stats";;
"readrandom")       benchmark="fillseq,fillrandom,readrandom,stats";;
"readreverse")      benchmark="fillseq,fillrandom,readreverse,stats";;
*)                  echo "Unknown db benchmark"; exit;;
esac

# run app with tool
prefix="time -p"
if [[ $GDB ]]; then  prefix="gdb --args";   fi
${prefix} env ${env} ${APPDIR}/build/db_bench --db=log --threads=5    \
    --num=${OPS} --benchmarks=${benchmark} 2>&1 | tee app.out

# back to app dir
popd

# post-processing
if [[ $MERGE_TRACES ]]; then

    # locate the binary
    binfile=${APPDIR}/build/db_bench
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

    mkdir -p ${expdir}/traces
    if [ -f ${expdir}/traces/000_000.txt ]; then
        echo "traces already exist for ${APP} at ${expdir}"
        continue
    fi

    # merge traces
    allfaultsin=$(ls ${expdir}/fault-samples-*.out)
    python3 ${ROOT_SCRIPTS_DIR}/parse_fltrace_samples.py -i ${allfaultsin}    \
        -b ${binfile} > ${expdir}/traces/000_000.txt

    # clean output
    if [ -f ${expdir}/traces/000_000.txt ]; then
        bash ${TOOLDIR}/analysis/clean_trace.sh ${expdir}/traces/000_000.txt
    fi
fi

if [[ $ANALYZE_TRACES ]]; then
    for cutoff in 100 95; do
        python3 ${TOOLDIR}/analysis/trace_codebase.py -d ${expdir}/traces   \
           -R -n ${APP} -c ${cutoff} -z > ${expdir}/flocations_nozero_${cutoff}.txt
        python3 ${TOOLDIR}/analysis/trace_codebase.py -d ${expdir}/traces   \
            -R -n ${APP} -c ${cutoff} > ${expdir}/flocations_${cutoff}.txt
    done
fi

# run succeeded
mkdir -p ${DATADIR}
mv ${expdir}/ $DATADIR/