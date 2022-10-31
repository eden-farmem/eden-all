#!/bin/bash
# set -e

# Fastswap plots

PLOTEXT=png
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
PLOTDIR=${SCRIPT_DIR}/plots
DATADIR=${SCRIPT_DIR}/data
BINFILE="${SCRIPT_DIR}/dataframe/build/bin/main"
TMP_FILE_PFX=tmp_df_plot_

source ${ROOT_SCRIPTS_DIR}/utils.sh

usage="\n
-f, --force \t\t force re-summarize data and re-generate plots\n
-fp, --force-plots \t force re-generate just the plots\n
-id, --plotid \t pick one of the many charts this script can generate\n
-r, --run \t run id if focusing on a single run\n
-h, --help \t\t this usage information message\n"

for i in "$@"
do
case $i in
    -f|--force)
    FORCE=1
    FORCE_PLOTS=1
    FORCE_FLAG="-f"
    ;;
    
    -fp|--force-plots)
    FORCE_PLOTS=1
    FORCEP_FLAG="-fp"
    ;;

    -id=*|--fig=*|--plotid=*)
    PLOTID="${i#*=}"
    ;;

    -r=*|--run=*)
    RUNID="${i#*=}"
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
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

# fault locations
if [ "$PLOTID" == "1" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    files=
    plots=

    ## data
    exp=run-09-21-12-26-23

    # get fault data
    datafile=$plotdir/fault_data_${exp}
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        expdir=${DATADIR}/$exp
        kfaultsin=${expdir}/kona_fault_samples.out
        if [ ! -f ${kfaultsin} ]; then 
            echo "kona_fault_samples.out not found for ${app} at ${expdir}"
            exit 1
        fi

        if [ ! -f ${BINFILE} ]; then 
            echo "binary not found at ${binfile}"
            exit 1
        fi
        python3 ${ROOT_SCRIPTS_DIR}/parse_kona_faults.py -i ${kfaultsin} -b ${BINFILE} > ${datafile}
    fi

    plotname=${plotdir}/fault_locations_cdf_${exp}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOT_SCRIPTS_DIR}/plot.py -z cdf --pdfdata            \
            -d ${datafile} -l "Dataframe"                               \
            -xl "Faulting locations" -yc "count" -yl "CDF of faults"    \
            --xmin 0 --xmax 100 --nomarker                              \
            --size 4 2.5 -fs 12 -of $PLOTEXT -o $plotname
    fi
    display ${plotname} &
fi

# cleanup
rm -f ${TMP_FILE_PFX}*