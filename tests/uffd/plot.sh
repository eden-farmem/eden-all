#!/bin/bash
set -e

#
# Plot figures for the paper
#

PLOTEXT=png
SCRIPT_DIR=`dirname "$0"`
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=${SCRIPT_DIR}/plots
DATADIR=${SCRIPT_DIR}/data
TMP_FILE_PFX='tmp_uffd_'

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

# setup
mkdir -p $PLOTDIR
mkdir -p $DATADIR


# gets data and fills $plots
add_data_to_plot() {
    group=$1
    label=$2
    cflag=$3
    share_uffd=$4
    hthr=$5

    if [ "$share_uffd" == "1" ]; then  sflag="";            fi
    if [ "$share_uffd" == "0" ]; then  sflag="--nosharefd"; fi
    if [[ $hthr ]]; then               hflag="-th=${hthr}"; fi

    datafile=${DATADIR}/${group}_${label}_xput.dat
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        echo "cores,xput,errors,latns" > $datafile
        for cores in 1 2 4 8 16; do 
            bash ${SCRIPT_DIR}/run.sh -t=$cores ${sflag} ${hflag} \
                -o="$cflag" -of=${datafile}
        done
    fi
    # cat $datafile
    plots="$plots -d $datafile -l $label"

    # gather latency numbers
    if [ ! -f $latfile ]; then  echo "config,latns" > $latfile; fi
    row2col3=`sed -n '2p' ${datafile} | awk -F, '{ print $4 }'`
    echo "$label,$row2col3" >> $latfile
}

# plots from $plots
generate_plots() {
    group=$1
    ymax=$2
    if [[ $ymax ]]; then ylflag="--ymin 0 --ymax ${ymax}"; fi

    plotname=${PLOTDIR}/${group}_xput.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python ${PLOTSRC} ${plots} ${ylflag}    \
            -yc xput -yl "MOPS" --ymul 1e-6     \
            -xc cores -xl "Cores"               \
            --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname
    fi
    display $plotname &

    if [[ $LATPLOT ]]; then
        plotname=${PLOTDIR}/${group}_latency.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            python3 ${PLOTSRC} -z bar -d ${latfile}     \
                -xc config -xl "Config"                 \
                -yc latns -yl "Cost (µs)" -ym 1e-3      \
                --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname 
        fi
        display $plotname &
    fi
}

plots=
latfile=${TMP_FILE_PFX}latency
rm -f $latfile

## benchmark UFFD copy
if [ "$PLOTID" == "1" ]; then
    add_data_to_plot "uffd_copy" "one_fd"       "-DMAP_PAGE" 1
    add_data_to_plot "uffd_copy" "fd_per_core"  "-DMAP_PAGE" 0
    generate_plots "uffd_copy"
fi

## benchmark Madvise
if [ "$PLOTID" == "2" ]; then
    plots=
    latfile=${TMP_FILE_PFX}latency
    rm -f $latfile
    add_data_to_plot "madv_dneed" "one_fd"      "-DUNMAP_PAGE" 1
    add_data_to_plot "madv_dneed" "fd_per_core" "-DUNMAP_PAGE" 0
    generate_plots   "madv_dneed"
fi

## benchmark entire fault path
if [ "$PLOTID" == "3" ]; then
    plots=
    sharefd=1
    YMAX=1.5
    for hthr in 1 2 4 8 11; do 
        add_data_to_plot "fault_path_one_fd" "hthr_$hthr" "-DACCESS_PAGE" $sharefd $hthr
    done
    generate_plots "fault_path_one_fd"     ${YMAX}

    plots=
    sharefd=0
    for hthr in 1 2 4 8 11; do 
        add_data_to_plot "fault_path_fd_per_core" "hthr_$hthr" "-DACCESS_PAGE" $sharefd $hthr
    done
    generate_plots "fault_path_fd_per_core" ${YMAX}
fi

# cleanup
rm -f ${TMP_FILE_PFX}*