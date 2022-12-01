#!/bin/bash
set -e

#
# Plots for the paper
#

#Defaults
PLOTEXT=pdf
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
PLOTDIR=${SCRIPT_DIR}/plots/paper/
DATADIR=${SCRIPT_DIR}/data

usage="\n
-id,  --plotid \t pick one of the many charts this script can generate\n
-h, --help \t\t this usage information message\n"

for i in "$@"
do
case $i in
    -id=*|--fig=*|--plotid=*)
    PLOTID="${i#*=}"
    ;;

    *)          # unknown option
    echo "Unknown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# point to last chart if not provided
if [ -z "$PLOTID" ]; then 
    PLOTID=`grep '"$PLOTID" == "."' $0 | wc -l`
    PLOTID=$((PLOTID-1))
fi

mkdir -p $PLOTDIR

# Raw fault benchmark: no eviction, local
if [ "$PLOTID" == "1" ]; then
    cfg=noevict-local-read
    plotname=${PLOTDIR}/micro-noevict-local.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
        -d ${DATADIR}/xput-fswap-${cfg}     -l "Fastswap"       -ls solid   -cmi 1      \
        -d ${DATADIR}/xput-nohints-${cfg}   -l "Eden (NH)"      -ls dashed  -cmi 0      \
        -d ${DATADIR}/xput-hints-${cfg}     -l "Eden"           -ls solid   -cmi 1      \
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 2.5  -xc cores -xl "CPU Cores"           \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname
    display ${plotname} &
fi

# Raw fault benchmark: no eviction, rdma
if [ "$PLOTID" == "2" ]; then
    cfg=noevict-rdma-read
    plotname=${PLOTDIR}/micro-noevict-rdma.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
        -d ${DATADIR}/xput-fswap-${cfg}     -l "Fastswap"       -ls solid   -cmi 1      \
        -d ${DATADIR}/xput-nohints-${cfg}   -l "Eden (NH)"      -ls dashed  -cmi 0      \
        -d ${DATADIR}/xput-bhints-${cfg}    -l "Eden (BH)"      -ls dashdot -cmi 0      \
        -d ${DATADIR}/xput-hints-${cfg}     -l "Eden"           -ls solid   -cmi 1      \
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 2.5  -xc cores -xl "CPU Cores"           \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname
    display ${plotname} &
fi

# Raw fault benchmark with read-ahead
if [ "$PLOTID" == "3" ]; then
    BACKEND=rdma
    cfg=noevict-${BACKEND}-read
    plotname=${PLOTDIR}/micro-rdahead-${BACKEND}.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
        -d ${DATADIR}/xput-hints-${cfg}     -l "0"   -ls solid      -cmi 0  \
        -d ${DATADIR}/xput-hints+1-${cfg}   -l "1"   -ls dotted     -cmi 0  \
        -d ${DATADIR}/xput-hints+2-${cfg}   -l "2"   -ls dashdot    -cmi 0  \
        -d ${DATADIR}/xput-hints+4-${cfg}   -l "4"   -ls dashed     -cmi 0  \
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 3.2 -xc cores -xl "CPU Cores"  \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "RdAhead"
    display ${plotname} &
fi

# Raw fault benchmark: with eviction
if [ "$PLOTID" == "4" ]; then
    BACKEND=local
    cfg=${BACKEND}-read
    plotname=${PLOTDIR}/micro-evict-${BACKEND}.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
        -d ${DATADIR}/xput-fswap-evict-${cfg}      -l "Fastswap"   -ls solid   -cmi 1  \
        -d ${DATADIR}/xput-hints-evict-${cfg}      -l "Eden (1)"   -ls dashed  -cmi 0  \
        -d ${DATADIR}/xput-hints-evict8-${cfg}     -l "Eden (8)"   -ls dashdot -cmi 0  \
        -d ${DATADIR}/xput-hints-evict16-${cfg}    -l "Eden (16)"  -ls solid   -cmi 1  \
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 2.5  -xc cores -xl "CPU Cores"          \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname
    display ${plotname} &
fi

# Raw fault benchmark: with dirty eviction
if [ "$PLOTID" == "5" ]; then
    BACKEND=local
    cfg=${BACKEND}-write
    plotname=${PLOTDIR}/micro-evict-dirty-${BACKEND}.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
        -d ${DATADIR}/xput-fswap-evict-${cfg}      -l "Fastswap"   -ls solid   -cmi 1  \
        -d ${DATADIR}/xput-hints-evict-${cfg}      -l "Eden (1)"   -ls dashed  -cmi 0  \
        -d ${DATADIR}/xput-hints-evict8-${cfg}     -l "Eden (8)"   -ls dashdot -cmi 0  \
        -d ${DATADIR}/xput-hints-evict16-${cfg}    -l "Eden (16)"  -ls solid   -cmi 1  \
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 2.5  -xc cores -xl "CPU Cores"          \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname
    display ${plotname} &
fi

