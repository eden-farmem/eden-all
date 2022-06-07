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
TMP_FILE_PFX='tmp_psrs_'

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
    FORCE_FLAG=" -f "
    ;;
    
    -fp|--force-plots)
    FORCE_PLOTS=1
    FORCEP_FLAG=" -fp "
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

# kona page fault time series
if [ "$PLOTID" == "1" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=
    VLINES=

    # take the most recent run if not specified
    latest_dir_path=$(ls -td -- $DATADIR/*/ | head -n 1)
    RUNID=${RUNID:-$(basename $latest_dir_path)}
    exp=$DATADIR/$RUNID

    # annotations
    annotations=${TMP_FILE_PFX}vlines
    start=`cat ${exp}/start`
    end=`cat ${exp}/end`
    if [[ $start ]]; then 
        echo "start,0"                                  >  $annotations
        echo "localsort,$((`cat ${exp}/phase1`-start))" >> $annotations
        echo "phase2,$((`cat ${exp}/phase2`-start))"    >> $annotations
        echo "merge,$((`cat ${exp}/phase4`-start))"     >> $annotations
        echo "copyback,$((`cat ${exp}/copyback`-start))">> $annotations
        echo "end,$((`cat ${exp}/end`-start))"          >> $annotations
        VLINES="--vlinesfile $annotations"
    fi

    # parse kona log
    konastatsout=${exp}/kona_counters_parsed
    konastatsin=${exp}/kona_counters.out 
    if [ ! -f $konastatsout ] && [ -f $konastatsin ]; then 
        python ${ROOT_SCRIPTS_DIR}/parse_kona_counters.py   \
            -i ${konastatsin} -o ${konastatsout}            \
            -st=${start} -et=${end}
    fi

    plotname=${plotdir}/faults_${RUNID}.${PLOTEXT}
    python ${ROOTDIR}/scripts/plot.py -d $konastatsout  \
        -yc n_faults    -l "total"      -ls solid       \
        -yc n_faults_r  -l "read"       -ls solid       \
        -yc n_faults_w  -l "write"      -ls solid       \
        -yc n_faults_wp -l "wrprotect"  -ls dashdot     \
        -yc n_evictions -l "evictions"  -ls dashed      \
        -xc "time" -xl "time (s)"  ${VLINES}            \
        -yl "KFPS" --ymul 1e-3  -nm --ymin 0 --ymax 150 \
        --size 10 4 -fs 11  -of $PLOTEXT  -o $plotname
    files="${files} ${plotname}"

    plotname=${plotdir}/memory_${RUNID}.${PLOTEXT}
    python ${ROOTDIR}/scripts/plot.py -d $konastatsout  \
        --ymul 1e-9 -yl "Memory (GB)"                   \
        -yc "malloc_size" -l "mallocd mem"              \
        -yc "mem_pressure" -l "working set"             \
        -xc "time" -xl "time (s)" ${VLINES} -nm         \
        --size 10 2 -fs 11  -of $PLOTEXT  -o $plotname
    files="${files} ${plotname}"

    # Combine
    plotname=${plotdir}/kona_stats_${RUNID}.$PLOTEXT
    montage -tile 0x3 -geometry +5+5 -border 5 $files ${plotname}
    rm -f ${files}
    display ${plotname} &
fi

# cleanup
rm -f ${TMP_FILE_PFX}*