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
env="$env FLTRACE_LOCAL_MEMORY_BYTES=10000000000" # based on the mem fingerprint
env="$env FLTRACE_MAX_MEMORY_MB=75000"                   # doesn't matter 
env="$env FLTRACE_NHANDLERS=1" # doesn't matter
# echo $env
## env end ##

cwpd=$PWD



# python3 /home/e7liu/eden-all/scripts/parse_fltrace_stat.py --maxrss -i /home/e7liu/eden-all/apps/coreutils/coreutils_output/sort-benchmark-random/raw/000/fault-stats-22748.out 

rm -r /home/e7liu/eden-all/apps/coreutils/coreutils_output/*

arr=("misc/sort-benchmark-random" "misc/cat-proc" )
pvs=(0 5 10 15 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95)
# arr=("misc/sort-benchmark-random" )
echo ${arr[0]}



for i in "${arr[@]}"
do
    for p in "${pvs[@]}"
    do 
        ####### Run individual test cases #######
        cd "$cwpd"
        # Insert a python file that adds the above env def to init.sh 
        python3 insert_env_to_init.py --percent=$p --name=$i

        cd "$cwpd"
        ## Modify the program
        python3 modify_test_sh.py --path=./coreutils/tests/$i.sh -d --percent=$p

        ## Actually running the program ##
        cd coreutils
        env RUN_VERY_EXPENSIVE_TESTS=yes ./tests/$i-modified.sh
        #########################################
    done
done





# ####### Run individual test cases #######
# cd "$cwpd"
# # Insert a python file that adds the above env def to init.sh 
# python3 insert_env_to_init.py --percent=$p --name=${arr[0]}

# cd "$cwpd"
# ## Modify the program
# python3 modify_test_sh.py --path=./coreutils/tests/${arr[0]}.sh -d --percent=$p

# ## Actually running the program ##
# cd coreutils
# env RUN_VERY_EXPENSIVE_TESTS=yes ./tests/${arr[0]}-modified.sh
# #########################################


