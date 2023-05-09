#!/bin/bash
set -e

#
# UFFD Benchmarks - generate and plot results
#

PLOTEXT=png
SCRIPT_DIR=`dirname "$0"`
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=${SCRIPT_DIR}/plots
DATADIR=${SCRIPT_DIR}/data
TMP_FILE_PFX='tmp_uffd_'
PTI=on

usage="\n
-f,   --force \t\t force re-summarize data and re-generate plots\n
-fp,  --force-plots \t force re-generate just the plots\n
-id,  --plotid \t pick one of the many charts this script can generate\n
-l,  --lat \t also plot latency numbers\n
-d,  --debug \t run programs in debug mode where applies\n
-h, --help \t\t this usage information message\n"

for i in "$@"
do
case $i in
    -f|--force)
    FORCE=1
    FORCE_PLOTS=1
    ;;
    
    -fp|--force-plots)
    FORCE_PLOTS=1
    ;;

    -np|--no-plots)
    NO_PLOTS=1
    ;;

    -id=*|--fig=*|--plotid=*)
    PLOTID="${i#*=}"
    ;;

    -l|--lat)
    LATPLOT=1
    ;;
    
    -d|--debug)
    DEBUG=1
    DEBUG_FLAG="-DDEBUG"
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

# PTI status
pti_msg=$(sudo dmesg | grep 'page tables isolation: enabled' || true)
if [ -z "$pti_msg" ]; then
    PTI=off
fi
echo "PTI status: $PTI"

# setup
mkdir -p $PLOTDIR
mkdir -p $DATADIR
LS=solid
CMI=1

# gets data and fills $plots
add_data_to_plot() {
    group=$1
    label=$2
    cores=$3
    cflags=$4

    datafile=${DATADIR}/${group}_${label}_pti_${PTI}.dat
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        echo "cores,batchsz,xput,errors,latns,memgb" > $datafile
        for batch in 1 2 4 8 16 32 64 128; do
            bash ${SCRIPT_DIR}/run.sh -c=$cores -bs=$batch  \
                -o="$cflags" -of=${datafile} --suppresslog
        done
    fi
    cat $datafile
    plots="$plots -d $datafile -l $label -ls $LS -cmi $CMI"

    # gather latency numbers
    if [ ! -f $latfile ]; then  echo "config,latns" > $latfile; fi
    row2col3=`sed -n '2p' ${datafile} | awk -F, '{ print $4 }'`
    echo "$label,$row2col3" >> $latfile
}

# plots from $plots
generate_xput_plot() {
    group=$1
    legend=$2
    ymax=$3
    if [[ $ymax ]]; then ylflag="--ymin 0 --ymax ${ymax}"; fi
    if [[ $NO_PLOTS ]]; then return; fi

    plotname=${PLOTDIR}/${group}_pti_${PTI}_xput.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${PLOTSRC} ${plots} ${ylflag}    \
            -yc xput -yl "MOPS" --ymul 1e-6     \
            -xc batchsz -xl "Batch size"        \
            --size 5 4 -fs 11 -of ${PLOTEXT} -o $plotname -lt "$legend"
    fi
    echo "generated plot at: $plotname"
}

plots=
latfile=${TMP_FILE_PFX}latency
rm -f $latfile

## benchmark UFFD copy
if [ "$PLOTID" == "1" ]; then
    YMAX=1
    add_data_to_plot "move_pages_1c_$(hostname)" "1" "1"
    add_data_to_plot "move_pages_2c_$(hostname)" "2" "2"
    add_data_to_plot "move_pages_4c_$(hostname)" "4" "4"
    add_data_to_plot "move_pages_8c_$(hostname)" "8" "8"
    generate_xput_plot "move_pages_$(hostname)" "CPU" ${YMAX}
fi

# cleanup
rm -f ${TMP_FILE_PFX}*