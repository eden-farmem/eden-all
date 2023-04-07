#!/bin/bash
# set -e

# synthetic app plots

PLOTEXT=png
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
PLOTDIR=${SCRIPT_DIR}/plots
DATADIR=${SCRIPT_DIR}/data
TMP_FILE_PFX=tmp_syn_plot_

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

# zipf curves
if [ "$PLOTID" == "1" ]; then
    plotdir=${PLOTDIR}/${PLOTID}
    mkdir -p ${plotdir}

    # take the latest run if not specified
    if [ -z "${RUNID}" ]; then
        RUNID=`ls -1 ${DATADIR} | grep "run-" | sort | tail -1`
    fi
    
    expdir=${DATADIR}/${RUNID}
    if [ ! -f "${expdir}/zipf_curve_0.txt" ]; then
        echo "Error: no zipf data at ${expdir}"
        exit
    fi
    lines=
    for f in `ls ${expdir}/zipf_curve_*.txt`; do
        lines="$lines -d $f"
        # add colname at top of each file if not present
        if [ `head -1 $f | grep -c "key"` == "0" ]; then
            echo "adding colname to $f"
            sed -i '1s/^/key\n/' $f
        fi
    done

    ## plot
    plotname=${plotdir}/zipf_curves.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py ${lines}            \
        -yc key -yl "Frequency %" -xl "Keys" --nomarker     \
        --size 6 3 -of $PLOTEXT -o $plotname -fs 11
    echo "saved plot to $plotname"
    # display $plotname &
fi


# cleanup
rm -f ${TMP_FILE_PFX}*