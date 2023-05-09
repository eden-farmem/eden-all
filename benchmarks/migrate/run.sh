#!/bin/bash
set -e

#
# Run page migrate benchmarks
# 

usage="\n
-d, --debug \t\t build debug\n
-o, --opts \t\t CFLAGS to include during build\n
-c, --cores \t\t number of cores to run on\n
-of, --outfile \t append results to this file\n
-g, --gdb \t run with debugging support\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
DATADIR=${SCRIPT_DIR}/data
BINFILE="measure.out"
TEMP_PFX=tmp_migrate_
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=${SCRIPT_DIR}/plots 
PLOTEXT=png
NCORES=1

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

    -c=*|--cores=*)
    NCORES="${i#*=}"
    ;;

    -bs=*|--batch=*)
    BATCH_SIZE="${i#*=}"
    CFLAGS="$CFLAGS -DBATCH_SIZE=$BATCH_SIZE"
    ;;

    -of=*|--outfile=*)
    OUTFILE="${i#*=}"
    ;;

    -sl|--suppresslog)
    CFLAGS="$CFLAGS -DSUPPRESS_LOG"
    ;;

    -g|--gdb)
    GDB=1
    CFLAGS="$CFLAGS -g -ggdb"           #for gdb
    CFLAGS="$CFLAGS -no-pie -fno-pie"   #no PIE/ASLR
    ;;

    -h|--help)
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
LDFLAGS="$LDFLAGS -lpthread -lnuma"
gcc measure.c utils.c ${CFLAGS} ${LDFLAGS} -o ${BINFILE}

# run
if [[ $OUTFILE ]]; then
    sudo ./${BINFILE} $NCORES | tee -a $OUTFILE
else
    sudo ./${BINFILE} $NCORES
fi

# cleanup
# rm ${BINFILE}
