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

# utils
mean() {
    VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ s += $0; n++ } 
            END { if (n > 0) printf "%.2f", s/n }'
    fi
}

stdev(){
    VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ x+=$0; y+=$0^2; n++ } 
            END { if (n > 0) printf "%.1f", sqrt(y/n-(x/n)^2)}'
    fi
}

# build
gcc measure.c region.c uffd.c parse_vdso.c ${DEBUG} -o ${OUTFILE}

# run
set +e    #to continue to cleanup even on failure
rm -f out
for i in `seq 1 1 25`; do 
    sudo ${env} ./${OUTFILE} | tee -a out
done

# analyze
samples=$(cat out | grep "Prefetch page time (on miss)" | grep -Eo "[0-9.]+ µs" | awk '{ print $1 }')
echo Result: $(mean "$samples") µs \(+/- $(stdev "$samples") µs\)


# cleanup
rm -f ${OUTFILE}
# rm -f out
