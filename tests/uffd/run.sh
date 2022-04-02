#!/bin/bash
set -e

#
# Test Nadav Amit's prefetch_page() API for Userfaultfd pages
# Requires this kernel patch/feature: 
# https://lore.kernel.org/lkml/20210225072910.2811795-4-namit@vmware.com/
# 

usage="\n
-d, --debug \t\t build debug\n
-f, --force \t\t force re-run experiments\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
DATADIR=${SCRIPT_DIR}/data
OUTFILE="prefetch.out"
TEMP_PFX=tmp_uffd_
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=${SCRIPT_DIR}/plots 
PLOTEXT=png
# UFFD_PER_THREAD=1   #assign different fd to each core

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -f|--force)
    FORCE=1
    ;;

    -p|--prefetch)
    CFLAGS="$CFLAGS -DUSE_PREFETCH"
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
rm -f ${OUTFILE}
LDFLAGS="$LDFLAGS -lpthread"
gcc measure.c region.c uffd.c utils.c parse_vdso.c ${CFLAGS} ${LDFLAGS} -o ${OUTFILE}

# run
set +e    #to continue to cleanup even on failure
mkdir -p ${DATADIR}
for UFFD_PER_THREAD in 0 1; do
    if [ "$UFFD_PER_THREAD" == "0" ]; then  label="one_fd_per_proc";    fi
    if [ "$UFFD_PER_THREAD" == "1" ]; then  label="one_fd_per_core";    fi
    datafile=${DATADIR}/uffd_xput_${label}
    if [ ! -f $datafile ] || [[ $FORCE ]]; then
        echo "cores,uffd_xput,uffd_err,madv_xput,madv_err" > $datafile
        for thr in 1 2 4 8 16; do 
            sudo ./${OUTFILE} $thr ${UFFD_PER_THREAD} >> $datafile
        done
    fi
    cat $datafile
    plots="$plots -d $datafile -l $label"
done

mkdir -p ${PLOTDIR}
plotname=${PLOTDIR}/uffd_copy_xput.${PLOTEXT}
python ${PLOTSRC} ${plots}          \
    -yc uffd_xput -yl "MOPS" --ymul 1e-6 \
    -xc cores -xl "Cores" --hlines 1 \
    --size 5 3 -fs 11 -of ${PLOTEXT} -o $plotname
display $plotname & 

plotname=${PLOTDIR}/madvise_xput.${PLOTEXT}
python ${PLOTSRC} ${plots}          \
    -yc madv_xput -yl "MOPS" --ymul 1e-6 \
    -xc cores -xl "Cores" --hlines 1 \
    --size 5 3 -fs 11 -of ${PLOTEXT} -o $plotname
display $plotname & 


# cleanup
rm ${OUTFILE}
rm ${TEMP_PFX}*
