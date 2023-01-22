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
-b, --bench \t\t rocks db benchmark to run\n
-f, --force \t\t force rebuild and re-run experiments\n
-d, --debug \t\t build debug\n
-sf, --safemode \t\t build in safemode\n
-g, --gdb \t\t build with symbols\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_PATH=`realpath $0`
SCRIPTDIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPTDIR}/../../../"
EDENDIR="${ROOTDIR}/eden"
# DATADIR="${SCRIPTDIR}/data/"
APPDIR="${SCRIPTDIR}/src/"
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')
MAX_REMOTE_MEMORY_BYTES=8000000000
MAX_REMOTE_MEMORY_MB=8000
LMEM=$((MAX_REMOTE_MEMORY_BYTES))
NHANDLERS=1

echo $SCRIPT_PATH

# save settings
SETTINGS=
save_cfg() {
    name=$1
    value=$2
    SETTINGS="${SETTINGS}$name:$value\n"
}

finish_exp() {
    popd
    d=`pwd`
    DATADIR=data
    echo "about to make a data dir in $d ${DATADIR}"
    mkdir -p ${DATADIR}
    mv ${expdir}/ $DATADIR/
    echo "successfully finished the script"
}


#make the experiment dir
start_exp() {
    echo "gonna run exp in: `pwd`"
    expdir=$EXPNAME
    mkdir -p $expdir
    pushd $expdir
    echo "running ${EXPNAME}"
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

    pushd src
    make
    make install
    popd
fi

start_exp

# save config
save_cfg "ops"              $OPS
save_cfg "localmem"         $LMEM
save_cfg "localmempercent"  $LMEMP
save_cfg "handlers"         $NHANDLERS
save_cfg "samples"          $SAMPLESPERSEC
save_cfg "desc"             $README
echo -e "$SETTINGS" > settings

# run app with tool
sudo sysctl -w vm.unprivileged_userfaultfd=1
prefix="time"
# if [[ $GDB ]]; then  prefix="gdb --args";   fi
# ${prefix} env ${env} ${APPDIR}/build/db_bench --db=log   \
    # --num=${OPS} --benchmarks=${benchmark} &> app.out
export LD_PRELOAD=${EDENDIR}/fltrace.so
export FLTRACE_LOCAL_MEMORY_BYTES="$LMEM"
export FLTRACE_MAX_MEMORY_MB=${MAX_REMOTE_MEMORY_MB}
export FLTRACE_NHANDLERS=${NHANDLERS}
if [[ $SAMPLESPERSEC ]]; then 
    export FLTRACE_MAX_SAMPLES_PER_SEC=$SAMPLESPERSEC
fi

echo "export LD_PRELOAD=$LD_PRELOAD"
echo "export FLTRACE_LOCAL_MEMORY_BYTES=$FLTRACE_LOCAL_MEMORY_BYTES"
echo "export FLTRACE_MAX_MEMORY_MB=${FLTRACE_MAX_MEMORY_MB}"
echo "export FLTRACE_NHANDLERS=$FLTRACE_NHANDLERS"