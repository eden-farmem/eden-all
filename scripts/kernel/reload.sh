#!/bin/bash
set -e

#
# Build & install a custom kernel
# Removes old kernel images & strips symbols to optimize for boot space
# (Should be run in linux source dir)
# Reboots if success
#

VERSION=
SCRIPT_DIR=`dirname "$0"`

usage="
-v, --version \t kernel version\n
-f, --force \t force override the warnings\n
-h, --headers \t update (global) headers as well \n
-h, --help \t this usage information message\n"

# parse cli
for i in "$@"
do
case $i in
    -v=*|--version=*)
    VERSION="${i#*=}"
    ;;

    -f|--force)
    FORCE=1
    FFLAG="-f"
    ;;

    -h|--headers)
    HEADERS=1
    ;;

    -t|--tools)
    TOOLS=1
    ;;
    
    -h | --help)
    echo -e $usage
    exit
    ;;

    *)                      # unknown option
    echo "Unknown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

make -j 40
sudo make modules_install -j 40
bash ${SCRIPT_DIR}/strip.sh -v=${VERSION} ${FFLAG}
bash ${SCRIPT_DIR}/remove.sh -v=${VERSION} ${FFLAG}
sudo make install 
if [[ $HEADERS ]]; then 
    sudo make headers_install INSTALL_HDR_PATH=/usr
fi
if [[ $TOOLS ]]; then 
    sudo apt-get install libpci-dev libpopt-dev
    make -C tools/perf
    sudo make -C tools/perf prefix=/usr/ install
fi
echo "ready to reboot"
sudo reboot