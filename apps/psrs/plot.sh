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
TMP_FILE_PFX='tmp_plot_psrs_'

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
    if ([[ $FORCE ]] || [ ! -f $konastatsout ]) && [ -f $konastatsin ]; then 
        python3 ${ROOT_SCRIPTS_DIR}/parse_kona_counters.py   \
            -i ${konastatsin} -o ${konastatsout}            \
            -st=${start} -et=${end}
    fi

    plotname=${plotdir}/faults_${RUNID}.${PLOTEXT}
    python3 ${ROOTDIR}/scripts/plot.py -d $konastatsout  \
        -yc n_faults    -l "total"      -ls solid       \
        -yc n_faults_r  -l "read"       -ls solid       \
        -yc n_faults_w  -l "write"      -ls solid       \
        -yc n_faults_wp -l "wrprotect"  -ls dashdot     \
        -yc n_evictions -l "evictions"  -ls dashed      \
        -xc "time" -xl "time (s)"  ${VLINES}            \
        -yl "KFPS" --ymul 1e-3  -nm --ymin 0 --ymax 150 \
        --size 10 2.5 -fs 11  -of $PLOTEXT  -o $plotname
    files="${files} ${plotname}"

    plotname=${plotdir}/app_faults_${RUNID}.${PLOTEXT}
    python3 ${ROOTDIR}/scripts/plot.py -d $konastatsout  \
        -yc n_afaults   -l "total (apt)"    -ls solid   \
        -yc n_afaults_r -l "read (apt)"     -ls dashed  \
        -yc n_afaults_w -l "write (apt)"    -ls dashdot \
        -xc "time" -xl "time (s)"  ${VLINES}            \
        -yl "KFPS" --ymul 1e-3  -nm --ymin 0 --ymax 150 \
        --size 10 2.5 -fs 11  -of $PLOTEXT  -o $plotname
    files="${files} ${plotname}"

    plotname=${plotdir}/memory_${RUNID}.${PLOTEXT}
    python3 ${ROOTDIR}/scripts/plot.py -d $konastatsout  \
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


# kona page fault time series
if [ "$PLOTID" == "2" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=
    BKEND_COL=3
    PFTYPE_COL=4
    TIME_COL=8


    pattern="06-12"; tperc=1;   desc="upcalls"; 
    cfg=tperc${tperc}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi
    for cores in 2; do 
        for kind in "baseline" "kona" "annot-sync" "annot-async"; do 

            case $kind in
            "baseline")     backend=none; pgf=none;;
            "kona")         backend=kona; pgf=none;;
            "annot-sync")   backend=kona; pgf=SYNC;;
            "annot-async")  backend=kona; pgf=ASYNC;;
            *)              echo "Unknown kind"; exit;;
            esac

            thr=$((cores*tperc))
            datafile=$plotdir/data_${cores}cores
            tmpfile=${TMP_FILE_PFX}_data
            rm -f $tmpfile
            if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
                bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -c=$cores \
                    -t=${thr} ${descopt} -of=$tmpfile -sc=shenango -pf=${pgf} -be=${backend}
            fi
            cat $datafile
        done
        plots="$plots -d $datafile -ls dashed -cmi 0"
    done

    # plotname=${plotdir}/faults_${RUNID}.${PLOTEXT}
    # python3 ${ROOTDIR}/scripts/plot.py -d $konastatsout  \
    #     -yc n_faults    -l "total"      -ls solid       \
    #     -yc n_faults_r  -l "read"       -ls solid       \
    #     -yc n_faults_w  -l "write"      -ls solid       \
    #     -yc n_faults_wp -l "wrprotect"  -ls dashdot     \
    #     -yc n_evictions -l "evictions"  -ls dashed      \
    #     -xc "time" -xl "time (s)"  ${VLINES}            \
    #     -yl "KFPS" --ymul 1e-3  -nm --ymin 0 --ymax 150 \
    #     --size 10 2.5 -fs 11  -of $PLOTEXT  -o $plotname
    # files="${files} ${plotname}"

    # # Combine
    # plotname=${plotdir}/kona_stats_${RUNID}.$PLOTEXT
    # montage -tile 0x3 -geometry +5+5 -border 5 $files ${plotname}
    # rm -f ${files}
    # display ${plotname} &
fi

# bar chart
if [ "$PLOTID" == "3" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=

    # DATA
    # pattern="07-05"; cores=1; tperc=1; desc="paper";
    # pattern="07-05"; cores=1; tperc=5; desc="paper";
    # pattern="07-05"; cores=2; tperc=1; desc="paper";
    pattern="07-05"; cores=2; tperc=5; desc="paper";

    # PARSE
    cfg=${cores}cores_tperc${tperc}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi
    thr=$((cores*tperc))
    datafile=$plotdir/data_${cfg}
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -c=$cores \
            -t=${thr} ${descopt} -of=$datafile --tag=${tag} --verbose
        cat $datafile
    fi

    # FORMAT
    for metric in "time" "idle" "faults"; do 
        colname=
        ylabel=
        ymax=
        ymul=
        case $metric in
        "time")         colname=Time;   ylabel="Time (s)";              ymax=500;   ymul=;;
        "idle")         colname=Idle;   ylabel="Idle Time (s)";         ymax=500;   ymul=;;
        "faults")       colname=Flts;   ylabel="Total Faults (1e6)";    ymax=15;    ymul=1e-6;;
        *)              echo "Unknown kind"; exit;;
        esac

        tmpfile=${TMP_FILE_PFX}${metric}
        echo "Phase",$(csv_column_as_str "$datafile" "Tag") > $tmpfile
        echo "Total",$(csv_column_as_str "$datafile" "${colname}(T)") >> $tmpfile
        echo "LocalSort",$(csv_column_as_str "$datafile" "${colname}(p1)") >> $tmpfile
        echo "Merge",$(csv_column_as_str "$datafile" "${colname}(p4)") >> $tmpfile
        echo "Copyback",$(csv_column_as_str "$datafile" "${colname}(cb)") >> $tmpfile
        cat $tmpfile

        # bar chart
        YSCALE=
        if [[ $ymax ]]; then YSCALE="--ymin 0 --ymax ${ymax}";  fi
        if [[ $ymul ]]; then YSCALE="${YSCALE} --ymul ${ymul}"; fi
        plotname=${plotdir}/bar_${metric}_${cfg}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            python3 ${ROOT_SCRIPTS_DIR}/plot.py -z bar  \
                -d ${tmpfile} -xc "Phase"           \
                -yc "pthreads"  -l "Pthr"           \
                -yc "uthreads"  -l "Uthr"           \
                -yc "sync"      -l "SYNC"           \
                -yc "async"     -l "ASYNC"          \
                -yc "async+"    -l "ASYNC+"         \
                -yl "${ylabel}" ${YSCALE} -xl " "   \
                --size 8 2.5 -fs 11 --barwidth 1 -of $PLOTEXT -o $plotname
        fi
        files="${files} ${plotname}"
    done

    # Combine
    plotname=${plotdir}/bar_all_${cfg}.$PLOTEXT
    montage -tile 0x3 -geometry +5+5 -border 5 $files ${plotname}
    rm -f ${files}
    display ${plotname} &
fi

# cleanup
rm -f ${TMP_FILE_PFX}*