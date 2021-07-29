#!/bin/bash
set -e

#
# Build Shenango and related app code
#

# Constants
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

if [[ $ONETIME ]]; then
    git submodule update --init --recursive
fi

if [[ $SYNC ]]; then 
    git pull --recurse-submodules
fi

if [[ $SHENANGO ]]; then 

    pushd shenango 
    make clean    
    if [[ $DPDK ]]; then    ./dpdk.sh;  fi
    make -j ${DEBUG}
    popd 

    pushd shenango/scripts
    gcc cstate.c -o cstate
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
    ./configure --with-shenango=$PWD/../shenango
    make clean
    make -j
    popd
fi

if [[ $SBENCH ]]; then
    pushd shenango/bindings
    make clean && make all
    popd
    pushd shenango/apps/bench
    make clean && make all
    popd
    # echo "Run `./shenango/iokerneld` and then `tbench tbench.config` "
fi

echo "ALL DONE!"
