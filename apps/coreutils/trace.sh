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
    make fltrace.so -j ${DEBUG} ${OPTS} PROVIDED_CFLAGS="""$SHEN_CFLAGS"""
    popd
fi
#### Above here builds the tool ####



# Build each application
LIBS="${LIBS} -lpthread -lm"
CFLAGS="$CFLAGS -DMERGE_RDAHEAD=0"
CFLAGS="$CFLAGS -no-pie -fno-pie"   # symbols
echo 0 | sudo tee /proc/sys/kernel/randomize_va_space #no ASLR

## Keep Above ##

## Replace with make coreuitil###
# gcc main.c qsort_custom.c -D_GNU_SOURCE -Wall -O ${INC} ${LIBS} ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

## Setting up the env ##
# sudo sysctl -w vm.unprivileged_userfaultfd=1    # to run without sudo
# env="$env LD_PRELOAD=./../../eden/fltrace.so" # setting LD pre load
# env="$env FLTRACE_LOCAL_MEMORY_MB=1" # based on the mem fingerprint
# env="$env FLTRACE_MAX_MEMORY_MB=16000"                   # doesn't matter 
# env="$env FLTRACE_NHANDLERS=1" # doesn't matter


# env="$env FLTRACE_MAX_SAMPLES_PER_SEC=1000"
# ls ${SHENANGO_DIR}/fltrace.so
# pwd
# echo "about to run cat"

# Insert a python file that changes the init.sh


## Actually running the program ##
cd coreutils
sudo make TESTS=tests/misc/cat-proc.sh VERBOSE=yes check




# cd coreutils
# make; ./tests/misc/cat-proc.sh
