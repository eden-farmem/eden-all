#!/bin/bash
set -e

#
# Micro-benchmarking Kona's page status checks
# 

usage="\n
-f, --force \t\t force re-run experiments and generate fresh data\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
ROOTDIR="${SCRIPT_DIR}/../.."
ROOT_SCRIPTS_DIR=${ROOTDIR}/scripts
PLOTSRC=${ROOT_SCRIPTS_DIR}/plot.py
PLOTDIR=plots 
DATADIR=data
PLOTEXT=png
LATFILE=latencies
TEMP_PFX=tmp_kona_

source ${ROOT_SCRIPTS_DIR}/utils.sh

# parse cli
for i in "$@"
do
case $i in
    -f|--force)
    FORCE=1
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

#Parameters
KC=CONFIG_WP
KO="-DNO_ZEROPAGE_OPT"  #to estimate normal faults after first access
CFLAGS_BEFORE="-DMEASURE_KONA_CHECKS -DLATENCY"
kind="appfaults"

for op in "read" "write"; do 
    CFLAGS="$CFLAGS_BEFORE"
    cfg=${kind}-${op}

    case $kind in
    "faults")           ;;
    "appfaults")        CFLAGS="$CFLAGS -DUSE_APP_FAULTS";;
    "mixed")            CFLAGS="$CFLAGS -DUSE_APP_FAULTS -DMIX_FAULTS";;
    *)                  echo "Unknown fault kind"; exit;;
    esac

    case $op in
    "read")             CFLAGS="$CFLAGS -DFAULT_OP=0";  LS=solid;   CMI=0;;
    "write")            CFLAGS="$CFLAGS -DFAULT_OP=1";  LS=dashed;  CMI=0;;
    "r+w")              CFLAGS="$CFLAGS -DFAULT_OP=2";  LS=dashdot; CMI=1;;
    *)                  echo "Unknown fault op"; exit;;
    esac

    datafile=$DATADIR/page-check-latency-${cfg}
    if [ ! -f $datafile ] || [[ $FORCE ]]; then 
        bash run.sh -f -kc="$KC" -ko="$KO" --buildonly  #rebuild kona
        tmpfile=${TEMP_PFX}out
        echo "faultkind,faultop,threads,mean,stdev" > ${datafile}
        for thr in `seq 1 1 1`; do
            rm -f ${LATFILE}
            bash run.sh -t=${thr} -fl="""$CFLAGS""" -o=${tmpfile}
            latmean=
            latstd=
            if [ -f ${LATFILE} ]; then
                latmean=$(csv_column_mean ${LATFILE} "latency")
                latstd=$(csv_column_stdev ${LATFILE} "latency")
            fi
            echo "$kind,$op,$thr,$latmean,$latstd" >> ${datafile}
        done
    fi
    cat $datafile
done

# cleanup
rm -f ${TEMP_PFX}*

