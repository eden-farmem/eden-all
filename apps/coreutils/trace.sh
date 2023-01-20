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
#### Above here builds the tool ####

# Build each application
LIBS="${LIBS} -lpthread -lm"
CFLAGS="$CFLAGS -DMERGE_RDAHEAD=0"
CFLAGS="$CFLAGS -no-pie -fno-pie"   # symbols
echo 0 | sudo tee /proc/sys/kernel/randomize_va_space #no ASLR

## Keep Above ##

## Replace with make coreuitil###
# gcc main.c qsort_custom.c -D_GNU_SOURCE -Wall -O ${INC} ${LIBS} ${CFLAGS} ${LDFLAGS} -o ${BINFILE}


## Definitions for the env variable ##
## Don't change the format below ##
## env start ##
sudo sysctl -w vm.unprivileged_userfaultfd=1     # to run without sudo
env="$env LD_PRELOAD=/home/e7liu/eden-all/eden/fltrace.so" # setting LD pre load
env="$env FLTRACE_LOCAL_MEMORY_MB=1" # based on the mem fingerprint
env="$env FLTRACE_MAX_MEMORY_MB=16000"                   # doesn't matter 
env="$env FLTRACE_NHANDLERS=1" # doesn't matter
## env end ##


# Insert a python file that adds the above env def to init.sh 
python3 insert_env_to_init.py

cwpd=$PWD




# ### Run individual test cases ###
# cd "$cwpd"
# ## Modify the program
# python3 modify_test_sh.py --path=./coreutils/tests/misc/cat-proc.sh -d --cmd=cat

# ## Actually running the program ##
# cd coreutils
# ./tests/misc/cat-proc-modified.sh

# ### Run individual test cases ###
# cd "$cwpd"
# ## Modify the program
# python3 modify_test_sh.py --path=./coreutils/tests/misc/cat-self.sh -d --cmd=cat

# ## Actually running the program ##
# cd coreutils
# ./tests/misc/cat-self-modified.sh


### Run individual test cases ###
cd "$cwpd"
## Modify the program
python3 modify_test_sh.py --path=./coreutils/tests/misc/sort-version.sh -d --cmd=sort

## Actually running the program ##
cd coreutils
./tests/misc/sort-version-modified.sh


### Run individual test cases ###
cd "$cwpd"
## Modify the program
python3 modify_test_sh.py --path=./coreutils/tests/misc/uniq-collate.sh -d --cmd=uniq

## Actually running the program ##
cd coreutils
./tests/misc/uniq-collate-modified.sh
