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
-ops, --rocksdbops \t\t rocksdb ops\n
-b, --bench \t\t rocks db benchmark to run\n
-f, --force \t\t force rebuild and re-run experiments\n
-d, --debug \t\t build debug\n
-sf, --safemode \t\t build in safemode\n
-g, --gdb \t\t build with symbols\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_PATH=`realpath $0`
SCRIPTDIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPTDIR}/../../"
EDENDIR="${ROOTDIR}/eden"
DATADIR="${SCRIPTDIR}/data/"
APPDIR="${SCRIPTDIR}/src/"
EXPNAME=run-$(date '+%m-%d-%H-%M-%S')
MAX_REMOTE_MEMORY_MB=1000
LMEM=$((MAX_REMOTE_MEMORY_MB))
NHANDLERS=1
#app specific
OPS=3000
BENCH=all

# save settings
SETTINGS=
save_cfg() {
    name=$1
    value=$2
    SETTINGS="${SETTINGS}$name:$value\n"
}

kill_apps() {
    # initialize run
    sudo killall httpd
    sudo killall ab
    sleep 1
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

kill_apps


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

# run app with tool
prefix="time"
# if [[ $GDB ]]; then  prefix="gdb --args";   fi
# ${prefix} env ${env} ${APPDIR}/build/db_bench --db=log   \
    # --num=${OPS} --benchmarks=${benchmark} &> app.out
export LD_PRELOAD=${EDENDIR}/fltrace.so
export FLTRACE_LOCAL_MEMORY_MB="$LMEM"
export FLTRACE_MAX_MEMORY_MB=${MAX_REMOTE_MEMORY_MB}
export FLTRACE_NHANDLERS=${NHANDLERS}
if [[ $SAMPLESPERSEC ]]; then 
    export FLTRACE_MAX_SAMPLES_PER_SEC=$SAMPLESPERSEC
fi

###########################################################################################
####### APACHE WEBSERVER
###########################################################################################

echo "export LD_PRELOAD=$LD_PRELOAD"
echo "export FLTRACE_LOCAL_MEMORY_MB=$FLTRACE_LOCAL_MEMORY_MB"
echo "export FLTRACE_MAX_MEMORY_MB=${FLTRACE_MAX_MEMORY_MB}"
echo "export FLTRACE_NHANDLERS=$FLTRACE_NHANDLERS"

echo "Starting APACHE"
../apache/httpd -X &

export -n LD_PRELOAD
ps -e | grep httpd

#run the apache benchmark tool
APACHE_PORT=1080
APACHE_RUNTIME=15
CONCURRENCY=3
BENCH_OUTPUT="apache_benchmark.log"
ab_command='/root/dependencies/apachebench-for-multi-url/ab'

APACHE_BENCH_FLAGS=(
    '-n 100000'
    '-r'
    '-c 5'
    '-L /root/eden-all/apps/nginx/url.txt'
    "http://127.0.0.1"
)

sleep 2
echo "($ab_command ${APACHE_BENCH_FLAGS[@]} | tee $BENCH_OUTPUT-$i)"
($ab_command ${APACHE_BENCH_FLAGS[@]} | tee $BENCH_OUTPUT-$i) &
sleep $APACHE_RUNTIME
echo "About to kill apps"
kill_apps

# nginx_pid=$!
# echo "nginx_pid $nginx_pid"
# # strings /proc/$nginx_pid/environ
# sleep $time_exp


# run succeeded
popd
mkdir -p ${DATADIR}
mv ${expdir}/ $DATADIR/
echo "successfully finished the script"