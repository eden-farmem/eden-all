#
# Run sort with fltrace tool
# 

usage="\n
-f, --force \t\t force re-run experiments\n
-d, --debug \t\t build debug\n
-sf, --safemode \t\t build in safemode\n
-g, --gdb \t\t build with symbols\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
ROOTDIR=${SCRIPT_DIR}/../..
SHENANGO_DIR="${ROOTDIR}/eden"
BINFILE="${SCRIPT_DIR}/main.out"
TMP_FILE_PFX=tmp_sort

source ${ROOTDIR}/scripts/utils.sh

# parse cli
for i in "$@"
do
case $i in
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

    -sl|--suppresslog)
    SUPPRESS_LOG=1
    echo waa
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
    pushd ${SHENANGO_DIR}
    if [[ $FORCE ]];        then    make clean;                         fi
    if [[ $SAFEMODE ]];     then    OPTS="$OPTS SAFEMODE=1";            fi
    if [[ $GDB ]];          then    OPTS="$OPTS GDB=1";                 fi
    if [[ $DEBUG ]];        then    OPTS="$OPTS DEBUG=1";               fi
    if [[ $SUPPRESS_LOG ]]; then    OPTS="$OPTS SUPPRESS_LOG=1";         fi
    make fltrace.so -j ${DEBUG} ${OPTS} PROVIDED_CFLAGS="""$SHEN_CFLAGS"""
    popd
fi

## simple
NTHREADS=5
NKEYS=1000000
LMEM=77594624

## large
# NTHREADS=10
# NKEYS=1000000000
# LMEM=7400000000

## setupenv
# echo 0 | sudo tee /proc/sys/kernel/randomize_va_space #no ASLR
# sudo sysctl -w vm.unprivileged_userfaultfd=1    # to run without sudo

# build sort
LIBS="${LIBS} -lpthread -lm"
CFLAGS="$CFLAGS -DMERGE_RDAHEAD=0"
CFLAGS="$CFLAGS -no-pie -fno-pie"   # symbols
gcc main.c qsort_custom.c -D_GNU_SOURCE -Wall -O ${INC} ${LIBS} ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

env="$env LD_PRELOAD=${SHENANGO_DIR}/fltrace.so"
env="$env FLTRACE_LOCAL_MEMORY_MB=$((LMEM/(1024*1024)))"
env="$env FLTRACE_MAX_MEMORY_MB=16000"
env="$env FLTRACE_NHANDLERS=1"
# env="$env FLTRACE_MAX_SAMPLES_PER_SEC=1000"

# run
if [[ $GDB ]]; then  prefix="gdb --args"; fi
start=$(date +%s)
${prefix} env ${env} ./main.out ${NKEYS} ${NTHREADS}
end=$(date +%s)
echo "Time taken: $((end-start)) seconds"

# cleanup
if [[ ${TMP_FILE_PFX} ]]; then
    rm -f ${TMP_FILE_PFX}*
fi