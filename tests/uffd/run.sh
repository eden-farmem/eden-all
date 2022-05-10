#!/bin/bash
set -e

#
# Test Nadav Amit's prefetch_page() API for Userfaultfd pages
# Requires this kernel patch/feature: 
# https://lore.kernel.org/lkml/20210225072910.2811795-4-namit@vmware.com/
# 

usage="\n
-d, --debug \t\t build debug\n
-o, --opts \t\t CFLAGS to include during build\n
-t, --thr \t\t number of threads/cores to run with\n
-nsu, --nosharefd \t do not a share uffd across threads\n
-th, --handlers \t\t number of handler threads/cores to handle fds\n
-of, --outfile \t\t append results to this file\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
DATADIR=${SCRIPT_DIR}/data
BINFILE="measure.out"
TEMP_PFX=tmp_uffd_
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=${SCRIPT_DIR}/plots 
PLOTEXT=png
NTHREADS=1
SHARE_UFFD=1
NHANDLERS=1

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -o=*|--opts=*)
    CFLAGS="$CFLAGS ${i#*=}"
    ;;

    -t=*|--thr=*)
    NTHREADS="${i#*=}"
    ;;

    -nsu|--nosharefd)
    SHARE_UFFD=0
    ;;

    -th=*|--handlers=*)
    NHANDLERS="${i#*=}"
    ;;

    -of=*|--outfile=*)
    OUTFILE="${i#*=}"
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
rm -f ${BINFILE}
LDFLAGS="$LDFLAGS -lpthread"
gcc measure.c region.c uffd.c utils.c parse_vdso.c ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

# run
if [[ $OUTFILE ]]; then
    sudo ./${BINFILE} $NTHREADS $SHARE_UFFD $NHANDLERS | tee -a $OUTFILE
else 
    sudo ./${BINFILE} $NTHREADS $SHARE_UFFD $NHANDLERS 
fi

# cleanup
rm ${BINFILE}
