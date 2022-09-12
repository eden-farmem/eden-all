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
        plots="$plots -d $datafile -ls dashed "
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

# bar chart for runtime and page faults
if [ "$PLOTID" == "3" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=
    PLOTEXT=pdf

    # DATA
    # pattern="07-05"; cores=1; tperc=1; lmem=1000; desc="paper";
    pattern="07-05"; cores=1; tperc=5; lmem=1000; desc="paper";
    # pattern="07-05"; cores=2; tperc=1; lmem=1000; desc="paper";
    # pattern="07-05"; cores=2; tperc=5; lmem=1000; desc="paper";
    # pattern="07-05"; cores=2; tperc=5; lmem=250; desc="paper";
    # pattern="07-05"; cores=2; tperc=10; lmem=250; desc="paper";
    # pattern="07-05"; cores=2; tperc=15; lmem=250; desc="paper";

    # PARSE
    cfg=${cores}cores_tperc${tperc}_lmem${lmem}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi
    thr=$((cores*tperc))
    datafile=$plotdir/data_${cfg}
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -c=$cores -lm=${lmem} \
            -t=${thr} ${descopt} -of=$datafile --tag=${tag} --verbose
        cat $datafile
    fi

    # FORMAT
    # for metric in "time" "idle" "faults"; do 
    for metric in "time"; do 
        colname=
        ylabel=
        ymax=
        ymul=
        case $metric in
        "time")         colname=Time;   ylabel="Time (s)";              ymax=400;   ymul=;;
        "idle")         colname=Idle;   ylabel="Idle Time (s)";         ymax=100;   ymul=;;
        "faults")       colname=Flts;   ylabel="Faults (millions)";     ymax=12.5;  ymul=1e-6;;
        *)              echo "Unknown kind"; exit;;
        esac

        tmpfile=${TMP_FILE_PFX}${metric}
        echo "Phase",$(csv_column_as_str "$datafile" "Tag") > $tmpfile
        echo "Total",$(csv_column_as_str "$datafile" "${colname}(T)") >> $tmpfile
        echo "LocalSort",$(csv_column_as_str "$datafile" "${colname}(p1)") >> $tmpfile
        echo "Merge",$(csv_column_as_str "$datafile" "${colname}(p4)") >> $tmpfile
        echo "Copy-back",$(csv_column_as_str "$datafile" "${colname}(cb)") >> $tmpfile
        cat $tmpfile

        # bar chart
        YSCALE=
        if [[ $ymax ]]; then YSCALE="--ymin 0 --ymax ${ymax}";  fi
        if [[ $ymul ]]; then YSCALE="${YSCALE} --ymul ${ymul}"; fi
        plotname=${plotdir}/bar_${metric}_${cfg}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            python3 ${ROOT_SCRIPTS_DIR}/plot.py -z bar  \
                -d ${tmpfile} -xc "Phase"           \
                -yc "nofaults"  -l "nofaults"       \
                -yc "pthreads"  -l "pthreads"       \
                -yc "uthreads"  -l "uthreads"       \
                -yc "sync"      -l "sync"           \
                -yc "async"     -l "async"          \
                -yc "async+"    -l "async+"         \
                -yl "${ylabel}" ${YSCALE} -xl " "   \
                --size 4 3 -fs 11 -of $PLOTEXT -o $plotname
        fi
        files="${files} ${plotname}"
        display ${plotname} &
    done
fi

# bar chart for idle time
if [ "$PLOTID" == "4" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=
    PLOTEXT=pdf

    # DATA
    # pattern="07-05"; cores=1; tperc=1; lmem=1000; desc="paper";
    pattern="07-05"; cores=1; tperc=5; lmem=1000; desc="paper";
    # pattern="07-05"; cores=2; tperc=1; lmem=1000; desc="paper";
    # pattern="07-05"; cores=2; tperc=5; lmem=1000; desc="paper";
    # pattern="07-05"; cores=2; tperc=5; lmem=250; desc="paper";
    # pattern="07-05"; cores=2; tperc=10; lmem=250; desc="paper";
    # pattern="07-05"; cores=2; tperc=15; lmem=250; desc="paper";

    # PARSE
    cfg=${cores}cores_tperc${tperc}_lmem${lmem}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi
    thr=$((cores*tperc))
    datafile=$plotdir/data_${cfg}
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -c=$cores -lm=${lmem} \
            -t=${thr} ${descopt} -of=$datafile --tag=${tag} --verbose
        cat $datafile
    fi

    # FORMAT
    ylabel="Idle Time (s)"
    ymax=500
    # for metric in "kidle" "uidle"; do 
    for metric in "time"; do
        colname=
        case $metric in
        "time")         colname=Time;;
        "uidle")        colname=UIdle;;
        "kidle")        colname=KIdle;;
        *)              echo "Unknown kind"; exit;;
        esac

        tmpfile=${TMP_FILE_PFX}${metric}
        echo "Phase",$(csv_column_as_str "$datafile" "Tag") > $tmpfile
        echo "Total",$(csv_column_as_str "$datafile" "${colname}(T)") >> $tmpfile
        echo "LocalSort",$(csv_column_as_str "$datafile" "${colname}(p1)") >> $tmpfile
        echo "Merge",$(csv_column_as_str "$datafile" "${colname}(p4)") >> $tmpfile
        echo "Copyback",$(csv_column_as_str "$datafile" "${colname}(cb)") >> $tmpfile
        cat $tmpfile
    done

    # bar chart
    YSCALE=
    if [[ $ymax ]]; then YSCALE="--ymin 0 --ymax ${ymax}";  fi
    if [[ $ymul ]]; then YSCALE="${YSCALE} --ymul ${ymul}"; fi
    plotname=${plotdir}/bar_${metric}_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOT_SCRIPTS_DIR}/plot.py -z bar              \
            -d ${tmpfile} -xc "Phase"                           \
            -yc "pthreads"  -l "pthreads"   -bs 1   -bhs "/"    \
            -yc "uthreads"  -l "uthreads"   -bs 1   -bhs "\\"   \
            -yc "sync"      -l "sync"       -bs 1   -bhs "o"    \
            -yc "async"     -l "async"      -bs 1   -bhs "O"    \
            -yc "async+"    -l "async+"     -bs 1   -bhs "."    \
            -yl "${ylabel}" ${YSCALE} -xl " "                   \
            --size 4 3 -fs 11 -of $PLOTEXT -o $plotname
    fi
    files="${files} ${plotname}"
    display ${plotname} &
fi

# kona page fault memory tracing
if [ "$PLOTID" == "5" ]; then
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
    konatstampsout=${exp}/kona_tstamps_parsed
    konatstampsin=${exp}/kona_fault_tstamps.out
    if ([[ $FORCE ]] || [ ! -f $konatstampsout ]) && [ -f $konatstampsin ]; then 
        python3 ${ROOT_SCRIPTS_DIR}/parse_kona_tstamps.py       \
            -i ${konatstampsin} -o ${konatstampsout}            \
            -st=${start} -et=${end}
    fi
    head -10 ${konatstampsout}

    plotname=${plotdir}/kona_fault_trace_${RUNID}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py -z scatter --nomarker    \
            -d $konatstampsout -yc address -yl "Address Space"      \
            -xc "time" -xl "time (s)" --xmul 1e-6   ${VLINES}       \
            --size 8 5 -fs 11  -of $PLOTEXT  -o $plotname
    fi
    files="${files} ${plotname}"
    display ${plotname} &
fi

# cdf chart for kona fault patterns
if [ "$PLOTID" == "6" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=
    PLOTEXT=pdf

    # DATA
    pattern="07-06"; cores=1; lmem=1000; desc="memorytrace";

    # PARSE
    if [[ $desc ]]; then descopt="-d=$desc"; fi
    tmpfile=${TMP_FILE_PFX}runs
    bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -c=$cores -lm=${lmem} ${descopt} -of=$tmpfile --simple
    for expname in $(csv_column $tmpfile "Exp"); do 
        expdir=${DATADIR}/${expname}
        faultstatsin=${expdir}/kona_fault_tstamps.out
        faultstatsout=${plotdir}/data_faults_pdf_${expname}
        if ([[ $FORCE ]] || [ ! -f $faultstatsout ]) && [ -f $faultstatsin ]; then
            echo "getting data for ${expname}"
            phase1start=`cat ${expdir}/phase1`
            phase1end=`cat ${expdir}/phase2`
            python3 ${ROOT_SCRIPTS_DIR}/parse_kona_tstamps.py       \
                -i ${faultstatsin} -o ${faultstatsout}              \
                -st=${phase1start} -et=${phase1end}
        fi
        cat ${faultstatsout}
    done

    # cdf chart
    # plot setting: colors = ['b', 'g', 'brown', 'c', 'k', 'orange', 'm','orangered','y']
    plotname=${plotdir}/cdf_fault_pattern_tpc1.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOT_SCRIPTS_DIR}/plot.py -z cdf --pdfdata                    \
            -xc "refaults" -xl "Repeat Faults Per Page" -yc "count"  --xmin 0 --xmax 12.5     \
            -d ${plotdir}/data_faults_pdf_run-07-06-09-35-24 -l "pthreads"      \
            -d ${plotdir}/data_faults_pdf_run-07-06-09-43-37 -l "uthreads"      \
            -d ${plotdir}/data_faults_pdf_run-07-06-09-51-42 -l "sync"          \
            -d ${plotdir}/data_faults_pdf_run-07-06-10-00-04 -l "async"         \
            --size 4 3 -fs 11 -of $PLOTEXT -o $plotname
    fi
    display ${plotname} &

    plotname=${plotdir}/cdf_fault_pattern_tpc5.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOT_SCRIPTS_DIR}/plot.py -z cdf --pdfdata                    \
            -xc "refaults" -xl "Repeat Faults Per Page" -yc "count" --xmin 0 --xmax 12.5      \
            -d ${plotdir}/data_faults_pdf_run-07-06-10-16-25 -l "pthreads"      \
            -d ${plotdir}/data_faults_pdf_run-07-06-10-23-09 -l "uthreads"      \
            -d ${plotdir}/data_faults_pdf_run-07-06-10-30-12 -l "sync"          \
            -d ${plotdir}/data_faults_pdf_run-07-06-10-37-42 -l "async"         \
            --size 4 3 -fs 11 -of $PLOTEXT -o $plotname
    fi
    display ${plotname} &
fi


# performance of async page faults with changing cores (with multiple runs for each data point)
## FOR PAPER
if [ "$PLOTID" == "7" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    CPUCOL=1
    TIMECOL=2
    PLOTEXT=pdf
    speedplots=

    ## data
    # pattern="05-1[89]";   bkend=kona; zipfs=1;    tperc=100;  desc="zip5-noht"; ymax=300
    pattern="07-06";   bkend=kona;  desc="paper-cores";  ymax=300

    cfg=be${bkend}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi

    for mem in 500 1000; do 
        tag=pthreads    #baseline
        basefile=$plotdir/data_lm${mem}_tag${tag}_${cfg}
        if [[ $FORCE ]] || [ ! -f "$basefile" ]; then
            echo "CPU,Time,Backend,Tag,Local_MB" > $basefile
            for cores in 1 2 4 8; do 
                tmpfile=${TMP_FILE_PFX}data
                rm -f ${tmpfile}
                bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -tg=${tag} \
                    -lm=${mem} -c=$cores -of=$tmpfile ${descopt} --simple
                cat $tmpfile
                mintime=$(csv_column_min $tmpfile "Time(s)")
                echo ${cores},${mintime},${bkend},${tag},${mem} >> ${basefile}
            done
        fi
        cat $basefile | awk -F, '{ print $'$TIMECOL' }' > ${TMP_FILE_PFX}_baseline_time
        cat $basefile

        tag=async+    #upcalls
        upcallfile=$plotdir/data_lm${mem}_tag${tag}_${cfg}
        if [[ $FORCE ]] || [ ! -f "$upcallfile" ]; then
            echo "CPU,Time,Backend,Tag,Local_MB" > $upcallfile
            for cores in 1 2 4 8; do 
                tmpfile=${TMP_FILE_PFX}data
                rm -f ${tmpfile}
                bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -tg=${tag} \
                    -lm=${mem} -c=$cores -of=$tmpfile ${descopt} --simple
                cat $tmpfile
                mintime=$(csv_column_min $tmpfile "Time(s)")
                echo ${cores},${mintime},${bkend},${tag},${mem} >> ${upcallfile}
            done
        fi
        cat $upcallfile | awk -F, '{ print $'$TIMECOL' }' > ${TMP_FILE_PFX}_upcall_time
        cat $upcallfile

        # speedup
        speedup=$plotdir/data_speedup_lm${mem}_${cfg}
        cat $basefile | awk -F, '{ print $'$CPUCOL' }' > ${TMP_FILE_PFX}_cpu
        paste ${TMP_FILE_PFX}_baseline_time ${TMP_FILE_PFX}_upcall_time     \
            | awk  'BEGIN  { print "speedup" }; 
                    NR>1   { if ($1 && $2)  print ($1-$2)*100/$1 
                            else            print ""    }' > ${TMP_FILE_PFX}_speedup
        paste -d, ${TMP_FILE_PFX}_cpu ${TMP_FILE_PFX}_speedup > ${speedup}
        memf=$(echo $mem | awk '{ printf "%.1f", $0*100.0/4000 }' )
        speedplots="$speedplots -d ${speedup} -l $memf%"
        cat $speedup
    done

    # plot speedup
    plotname=${plotdir}/speedup_${cfg}.${PLOTEXT}
    echo $speedplots
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${speedplots} -z bar --xstr \
            -yc speedup -yl "Gain (%)" --ymin 0 --ymax 30   \
            -xc CPU -xl "CPU Cores"                         \
            --size 4 3 -fs 13 -of $PLOTEXT -o $plotname -lt "Local Memory"
    fi
    display ${plotname} &
fi


# bar charts with idle time split
if [ "$PLOTID" == "8" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=
    PLOTEXT=png

    # DATA
    # pattern="07-05"; cores=1; tperc=1; lmem=1000; desc="paper";
    pattern="07-05"; cores=1; tperc=5; lmem=1000; desc="paper";
    # pattern="07-05"; cores=2; tperc=1; lmem=1000; desc="paper";
    # pattern="07-05"; cores=2; tperc=5; lmem=1000; desc="paper";
    # pattern="07-05"; cores=2; tperc=5; lmem=250; desc="paper";
    # pattern="07-05"; cores=2; tperc=10; lmem=250; desc="paper";
    # pattern="07-05"; cores=2; tperc=15; lmem=250; desc="paper";

    # PARSE
    cfg=${cores}cores_tperc${tperc}_lmem${lmem}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi
    thr=$((cores*tperc))
    datafile=$plotdir/data_${cfg}
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -c=$cores -lm=${lmem} \
            -t=${thr} ${descopt} -of=$datafile --tag=${tag} --verbose
        cat $datafile
    fi

    # FORMAT
    datapfx=${TMP_FILE_PFX}
    for metric in  "time" "faults" "kidle" "uidle"; do 
        colname=
        case $metric in
        "time")         colname=Time;;
        "uidle")        colname=UIdle;;
        "kidle")        colname=KIdle;;
        "faults")       colname=Flts;;
        *)              echo "Unknown kind"; exit;;
        esac

        tmpfile=${datapfx}${metric}
        echo "Phase",$(csv_column_as_str "$datafile" "Tag") > $tmpfile
        echo "Total",$(csv_column_as_str "$datafile" "${colname}(T)") >> $tmpfile
        echo "LocalSort",$(csv_column_as_str "$datafile" "${colname}(p1)") >> $tmpfile
        echo "Merge",$(csv_column_as_str "$datafile" "${colname}(p4)") >> $tmpfile
        echo "Copyback",$(csv_column_as_str "$datafile" "${colname}(cb)") >> $tmpfile
        cat $tmpfile
    done

    # time bar chart
    metric=time
    YSCALE="--ymin 0 --ymax 400"
    plotname=${plotdir}/bar_${metric}_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOT_SCRIPTS_DIR}/plot.py -z bar  \
            -d ${datapfx}${metric} -xc "Phase"  \
            -yc "nofaults"  -l "nofaults"       \
            -yc "pthreads"  -l "pthreads"       \
            -yc "uthreads"  -l "uthreads"       \
            -yc "sync"      -l "sync"           \
            -yc "async"     -l "async"          \
            -yc "async+"    -l "async+"         \
            -yl "Time (s)" ${YSCALE} -xl " "    \
            --size 4 3 -fs 11 -of $PLOTEXT -o $plotname
    fi
    files="${files} ${plotname}"
    
    # idle time bar chart
    metric=idle
    YSCALE="--ymin 0 --ymax 100"
    plotname=${plotdir}/bar_${metric}_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOT_SCRIPTS_DIR}/plot.py -z bar  -xc "Phase"                         \
            -dyc ${datapfx}kidle "nofaults" -l "nofaults"   -bs 1   -bhs "/"    -cmi 0  \
            -dyc ${datapfx}uidle "nofaults" -l " "          -bs 0   -bhs "."    -cmi 1  \
            -dyc ${datapfx}kidle "pthreads" -l "pthreads"   -bs 1   -bhs "/"    -cmi 0  \
            -dyc ${datapfx}uidle "pthreads" -l " "          -bs 0   -bhs "."    -cmi 1  \
            -dyc ${datapfx}kidle "uthreads" -l "uthreads"   -bs 1   -bhs "/"    -cmi 0  \
            -dyc ${datapfx}uidle "uthreads" -l " "          -bs 0   -bhs "."    -cmi 1  \
            -dyc ${datapfx}kidle "sync"     -l "sync"       -bs 1   -bhs "/"    -cmi 0  \
            -dyc ${datapfx}uidle "sync"     -l " "          -bs 0   -bhs "."    -cmi 1  \
            -dyc ${datapfx}kidle "async"    -l "async"      -bs 1   -bhs "/"    -cmi 0  \
            -dyc ${datapfx}uidle "async"    -l " "          -bs 0   -bhs "."    -cmi 1  \
            -dyc ${datapfx}kidle "async+"   -l "async+"     -bs 1   -bhs "/"    -cmi 0  \
            -dyc ${datapfx}uidle "async+"   -l " "          -bs 0   -bhs "."    -cmi 1  \
            -yl "Idle Time (s)" -xl " " ${YSCALE} --size 4 3 -fs 11 -of $PLOTEXT -o $plotname
    fi
    files="${files} ${plotname}"

    # faults bar chart
    metric=faults
    YSCALE="--ymin 0 --ymax 13 --ymul 1e-6"
    plotname=${plotdir}/bar_${metric}_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOT_SCRIPTS_DIR}/plot.py -z bar  \
            -d ${datapfx}${metric} -xc "Phase"      \
            -yc "nofaults"  -l "nofaults"           \
            -yc "pthreads"  -l "pthreads"           \
            -yc "uthreads"  -l "uthreads"           \
            -yc "sync"      -l "sync"               \
            -yc "async"     -l "async"              \
            -yc "async+"    -l "async+"             \
            -yl "Faults (millions)" ${YSCALE} -xl " "   \
            --size 4 3 -fs 11 -of $PLOTEXT -o $plotname
    fi
    files="${files} ${plotname}"

    # Combine
    plotname=${plotdir}/bar_charts_${cfg}.$PLOTEXT
    montage -tile 3x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi

# cleanup
rm -f ${TMP_FILE_PFX}*