#!/bin/bash
set -e

#
# Test Nadav Amit's prefetch_page() API for Userfaultfd pages
# Requires this kernel patch/feature: 
# https://lore.kernel.org/lkml/20210225072910.2811795-4-namit@vmware.com/
# 

usage="\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
OUTFILE="prefetch.out"

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    DEBUG="-DDEBUG"
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

# build
gcc measure.c region.c uffd.c parse_vdso.c ${DEBUG} -o ${OUTFILE}

# run
set +e    #to continue to cleanup even on failure
sudo ${env} ./${OUTFILE}

# cleanup
rm ${OUTFILE}
