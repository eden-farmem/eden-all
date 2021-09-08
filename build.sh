#!/bin/bash
set -e

#
# Build Shenango, Kona and other related app code
#

usage="\n
-d, --debug \t\t build debug\n
-o, --onetime \t\t first time (includes some one-time init stuff)\n
-n, --sync \t\t sync code base from git (for syncing updates on other machines)\n
-s, --shenango \t\t build shenango core\n
-sd,--sdpdk \t\t include dpdk in the build\n
-m, --memcached \t\t build memcached app\n
-sy,--synthetic \t\t build shenango synthetic app\n
-sb,--sbench \t\t build shenango bench app\n
-k,--kona \t\t build kona\n
-mk,--with-kona \t\t build memcached + shenango linked with kona\n
-a, --all \t\t build everything\n
-h, --help \t\t this usage information message\n"

# Parse command line arguments
for i in "$@"
do
case $i in
    -d|--debug)
    DEBUG="DEBUG=1"
    ;;

    -o|--onetime)
    ONETIME=1
    ;;

    -n|--sync)
    SYNC=1
    ;;

    -s|--shenango)
    SHENANGO=1
    ;;

    -sd|--dpdk)
    DPDK=1
    ;;

    -m|--memcached)
    SHENANGO=1
    MEMCACHED=1
    ;;

    -sy|--synthetic)
    SHENANGO=1
    SYNTHETIC=1
    ;;

    -sb|--sbench)
    SHENANGO=1
    SBENCH=1
    ;;


    -k|--kona)
    KONA=1
    ;;
    
    -kc=*|--kona-config=*)
    kona_cfg="PBMEM_CONFIG=${i#*=}"
    ;;

    -mk|--with-kona)
    WITH_KONA=1
    ;;

    -a|--all)
    SHENANGO=1
    MEMCACHED=1
    SYNTHETIC=1
    ;;

    # -o=*|--opts=*)    # options 
    # OPTS="${i#*=}"
    # ;;

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

# Initial CPU allocation
# NUMA node0 CPU(s):   0-13,28-41
# NUMA node1 CPU(s):   14-27,42-55
# RNIC NUMA node = 1
NUMA_NODE=1
KONA_POLLER_CORE=53
KONA_EVICTION_CORE=54
KONA_FAULT_HANDLER_CORE=55
KONA_ACCOUNTING_CORE=52
SHENANGO_EXCLUDE=${KONA_POLLER_CORE},${KONA_EVICTION_CORE},${KONA_FAULT_HANDLER_CORE},${KONA_ACCOUNTING_CORE}

if [[ $ONETIME ]]; then
    git submodule update --init --recursive
    pushd kona/
    # can the above command not do this too?
    git submodule update --init --recursive
    popd
fi

if [[ $SYNC ]]; then 
    git pull --recurse-submodules
fi

if [[ $SHENANGO ]]; then 
    pushd shenango 
    make clean    
    if [[ $DPDK ]]; then    ./dpdk.sh;  fi
    if [[ $WITH_KONA ]]; then   KONA_OPT="WITH_KONA=1"; fi
    make -j ${DEBUG} NUMA_NODE=${NUMA_NODE} EXCLUDE_CORES=${SHENANGO_EXCLUDE} $KONA_OPT 
    popd 

    pushd shenango/scripts
    gcc cstate.c -o cstate
    popd
fi

if [[ $KONA ]]; then 
    pushd kona/pbmem
    make je_clean
    make clean
    make je_jemalloc
    core_opts="POLLER_CORE=$KONA_POLLER_CORE FAULT_HANDLER_CORE=$KONA_FAULT_HANDLER_CORE EVICTION_CORE=$KONA_EVICTION_CORE ACCOUNTING_CORE=${KONA_ACCOUNTING_CORE}"
    make all -j $core_opts $kona_cfg
    popd
fi

if [[ $SYNTHETIC ]]; then 
    if [[ $ONETIME ]]; then 
        # Install rust
        curl https://sh.rustup.rs -sSf | sh
        rustup default nightly-2020-06-06
    fi
    
    pushd shenango/apps/synthetic
    source $HOME/.cargo/env
    cargo clean
    cargo update
    cargo build --release
    popd
fi

if [[ $MEMCACHED ]]; then
    pushd memcached/
    ./autogen.sh 
    if [[ $WITH_KONA ]]; then   KONA_OPT="--with-kona=../kona"; fi
    ./configure --with-shenango=$PWD/../shenango $KONA_OPT
    make clean
    make -j
    popd
fi

if [[ $SBENCH ]]; then
    pushd shenango/bindings/cc
    make clean && make all
    popd
    pushd shenango/apps/bench
    make clean && make all -j
    popd
    # echo "Run `./shenango/iokerneld` and then `tbench tbench.config` "
fi

echo "ALL DONE!"
