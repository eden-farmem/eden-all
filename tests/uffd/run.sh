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
TEMP_PFX=tmp_uffd_
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=plots 
PLOTEXT=png

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
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
LDFLAGS="$LDFLAGS -lpthread"
gcc measure.c region.c uffd.c utils.c parse_vdso.c ${CFLAGS} ${LDFLAGS} -o ${OUTFILE}

# run
set +e    #to continue to cleanup even on failure
datafile=${TEMP_PFX}uffd
echo "cores,xput_per_core" > $datafile
for thr in 1 2 4 8 16; do 
    sudo ./${OUTFILE} $thr >> $datafile
done

cat $datafile
mkdir -p ${PLOTDIR}
plotname=uffd_copy_xput.${PLOTEXT}
python ${PLOTSRC} -d $datafile -l "UFFD Copy"       \
    -xc cores -xl "Cores"  --ymin 0 --ymax 0.5      \
    -yc xput_per_core -yl "Mops/core" --ymul 1e-6   \
    --size 5 3 -fs 11 -of ${PLOTEXT} -o $plotname
display $plotname & 

# cleanup
rm ${OUTFILE}
rm ${TEMP_PFX}*
