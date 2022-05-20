#!/bin/bash
# set -e

# Fastswap plots

PLOTEXT=png
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
PLOTDIR=${SCRIPT_DIR}/plots
DATADIR=${SCRIPT_DIR}/data
TMP_FILE_PFX=tmp_syn_plot_

usage="\n
-f, --force \t\t force re-summarize data and re-generate plots\n
-fp, --force-plots \t force re-generate just the plots\n
-id, --plotid \t pick one of the many charts this script can generate\n
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

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

#Defaults
TMP_FILE_PFX='tmp_paper_'
PLOTLIST=${TMP_FILE_PFX}plots

# point to last chart if not provided
if [ -z "$PLOTID" ]; then 
    PLOTID=`grep '"$PLOTID" == "."' $0 | wc -l`
    PLOTID=$((PLOTID-1))
fi

mkdir -p $PLOTDIR

add_plot_group() {
    # filters
    pattern=$1
    backend=$2
    pgfaults=$3
    zparams=$4
    tperc=$5
    cores=$6
    if [[ $7 ]]; then descopt="-d=$7"; fi

    datafile=$plotdir/data_${cores}cores_be${backend}_pgf${pgfaults}_zs${zparams}_tperc${tperc}
    thr=$((cores*tperc))
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgfaults \
            -c=$cores -of=$datafile -t=${thr} -zs=${zparams} ${descopt}
    fi
    plots="$plots -d $datafile"
}

# performance with kona/page faults
if [ "$PLOTID" == "1" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=

    ## data
    # pattern="05-\(09-23\|10-0[01234]\|10-05-[012]\)";  bkend=kona; pgf=none;   zipfs=0.1;  tperc=1;
    # pattern="05-\(09-23\|10-0[01234]\|10-05-[012]\)";  bkend=kona; pgf=SYNC;   zipfs=0.1;  tperc=1;
    # pattern="05-\(09-23\|10-0[01234]\|10-05-[012]\)";  bkend=kona; pgf=ASYNC;  zipfs=0.1;  tperc=1;
    # pattern="05-10-\(09\|10\)";    bkend=kona; pgf=ASYNC;  zipfs=0.1;  tperc=10;
    # pattern="05-10-\(09\|1\)";     bkend=kona; pgf=ASYNC;  zipfs=0.1;  tperc=60;
    # pattern="05-11";               bkend=kona; pgf=ASYNC;  zipfs=0.1;  tperc=60;
    # pattern="05-11";               bkend=kona; pgf=ASYNC;  zipfs=0.1;  tperc=110;
    # pattern="05-11";               bkend=kona; pgf=ASYNC;  zipfs=0.1;  tperc=160;
    # pattern="05-11";               bkend=kona; pgf=ASYNC;  zipfs=0.1;  tperc=210;
    # pattern="05-\(11-23\|12\)";    bkend=kona; pgf=none;   zipfs=0.5;  tperc=100;
    # pattern="05-\(11-23\|12\)";    bkend=kona; pgf=ASYNC;  zipfs=0.5;  tperc=100;
    # pattern="05-\(11-23\|12\)";    bkend=kona; pgf=none;   zipfs=1;    tperc=100;
    # pattern="05-\(11-23\|12\)";    bkend=kona; pgf=ASYNC;  zipfs=1;    tperc=100;

    cfg=be${bkend}_pgf${pgf}_zs${zipfs}_tperc${tperc}
    for cores in 1 2 3 4 5; do
        label=$cores
        datafile=$plotdir/data_${cores}cores_${cfg}
        thr=$((cores*tperc))
        if [[ $desc ]]; then descopt="-d=$desc"; fi
        if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
            bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgf     \
                -c=$cores -of=$datafile -t=${thr} -zs=${zipfs} ${descopt}
        fi
        plots="$plots -d $datafile -l $label"
        cat $datafile
    done

    #plot xput
    YLIMS="--ymin 0 --ymax 1000"
    plotname=${plotdir}/xput_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py ${plots}   \
            -yc Xput -yl "Xput KOPS" --ymul 1e-3 ${YLIMS}   \
            -xc Local_MB -xl "Local Memo MB)"               \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    fi
    files="$files $plotname"

    #plot faults
    YLIMS="--ymin 0 --ymax 150"
    plotname=${plotdir}/rfaults_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py ${plots}               \
            -yc "ReadPF" -yl "Read Faults KOPS" --ymul 1e-3 ${YLIMS}    \
            -xc Local_MB -xl "Local Mem (MB)"                           \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    fi
    files="$files $plotname"

    #plot faults
    plotname=${plotdir}/rafaults_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py ${plots}               \
            -yc "ReadAPF" -yl "Read App Faults" --ymul 1e-3 ${YLIMS}     \
            -xc Local_MB -xl "Local Mem (MB)"                           \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    fi
    files="$files $plotname"

    # #plot faults
    # plotname=${plotdir}/wpfaults_${cfg}.${PLOTEXT}
    # if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
    #     python3 ${SCRIPT_DIR}/../scripts/plot.py ${plots}               \
    #         -yc "WPFaults" -yl "WP Faults KOPS" --ymul 1e-3 ${YLIMS}    \
    #         -xc Local_MB -xl "Local Mem (MB)"                           \
    #         --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    # fi
    # files="$files $plotname"

    # # Combine
    plotname=${plotdir}/all_${cfg}.$PLOTEXT
    montage -tile 3x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi


# hash table lookup performance under various locking scenarios
if [ "$PLOTID" == "2" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    files=
    runs="05-09"
    for zparams in 0.1 0.5 1; do 
        plots=
        for buckets in "" 100 1000 10000; do 
            case $buckets in
            "")                 desc=-DLOCK_INSIDE_BUCKET; LABEL="within";;
            *)                  desc="-DBUCKETS_PER_LOCK=$buckets"; LABEL="$buckets";;
            esac

            datafile=$plotdir/data_buckets_per_lock_${LABEL}_zs${zparams}
            if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
                bash ${SCRIPT_DIR}/show.sh -s="$runs" -d="$desc" -zs=${zparams} -of=${datafile}
            fi
            plots="$plots -d $datafile -l $LABEL"
            cat $datafile
        done

        #plot xput
        YLIMS="--ymin 0 --ymax 4"
        plotname=${plotdir}/xput_buckets_per_lock_zs${zparams}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            python3 ${SCRIPT_DIR}/../scripts/plot.py ${plots}   \
                -yc XputPerCore -yl "MOPS / core" --ymul 1e-6 ${YLIMS}        \
                -xc CPU -xl "CPU cores"                         \
                --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "BucketsPerLock"
        fi
        files="$files $plotname"
    done

    # # Combine
    plotname=${plotdir}/xput_lock_contention.$PLOTEXT
    montage -tile 3x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi

# performance with kona/page faults with baseline on the same chart
if [ "$PLOTID" == "3" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    speedplots=
    cmiopts=
    linestyles=
    files=
    LMEMCOL=6
    XPUTCOL=9
    ymax=1000

    ## data
    # pattern="05-1[56]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip"
    # pattern="05-1[56]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip+"
    # pattern="05-1[78]";    bkend=kona; zipfs=1;    tperc=100;  desc="noht"        ymax=2500
    # pattern="05-1[89]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip5-noht"   ymax=700
    # pattern="05-1[89]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip50-noht"  ymax=75
    # pattern="05-1[89]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip500-noht" ymax=10

    cfg=be${bkend}_zs${zipfs}_tperc${tperc}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi
    for cores in 1 2 3 4 5; do 
        thr=$((cores*tperc))
        speedup=$plotdir/data_speedup_${cores}cores_${cfg}

        pgf=none    #baseline
        datafile=$plotdir/data_${cores}cores_pgf${pgf}_${cfg}
        if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
            bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgf \
                -c=$cores -of=$datafile -t=${thr} -zs=${zipfs} ${descopt}
        fi
        plots="$plots -d $datafile -ls dashed -cmi 0"
        cat $datafile | awk -F, '{ print $'$XPUTCOL' }' > ${TMP_FILE_PFX}_baseline_xput
        cat $datafile

        pgf=ASYNC    #upcalls
        datafile=$plotdir/data_${cores}cores_pgf${pgf}_${cfg}
        if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
            bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgf \
                -c=$cores -of=$datafile -t=${thr} -zs=${zipfs} ${descopt}
        fi
        plots="$plots -d $datafile -ls solid -cmi 1"
        cat $datafile | awk -F, '{ print $'$XPUTCOL' }' > ${TMP_FILE_PFX}_upcall_xput
        cat $datafile 

        cat $datafile | awk -F, '{ print $'$LMEMCOL' }' > ${TMP_FILE_PFX}_lmem
        paste ${TMP_FILE_PFX}_baseline_xput ${TMP_FILE_PFX}_upcall_xput     \
            | awk  'BEGIN  { print "speedup" }; 
                    NR>1   { if ($1 && $2)  print $2/$1 
                            else            print ""    }' > ${TMP_FILE_PFX}_speedup
        paste -d, ${TMP_FILE_PFX}_lmem ${TMP_FILE_PFX}_speedup > ${speedup}
        speedplots="$speedplots -d ${speedup} -l $cores"
        cat $speedup
    done

    # plot xput
    YLIMS="--ymin 0 --ymax $ymax"
    plotname=${plotdir}/xput_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py ${plots}   \
            -yc Xput -yl "Xput KOPS" --ymul 1e-3 ${YLIMS}   \
            -xc Local_MB -xl "Local Mem MB"                 \
            -l "1" -l "" -l "2" -l ""                       \
            -l "3" -l "" -l "4" -l "" -l "5" -l ""          \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    fi
    files="$files $plotname"

    #plot faults
    YLIMS="--ymin 0 --ymax 200"
    plotname=${plotdir}/faults_$cfg.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py ${plots}               \
            -yc "ReadPF" -yl "Page Faults" --ymul 1e-3 ${YLIMS}         \
            -xc Local_MB -xl "Local Mem (MB)"                           \
            -l "" -l "" -l "" -l ""                                     \
            -l "" -l "" -l "" -l "" -l "" -l ""                         \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    #plot speedup
    YLIMS="--ymin 1 --ymax 3"
    plotname=${plotdir}/speedup_$cfg.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py ${speedplots}  \
            -yc "speedup" -yl "Speedup"                         \
            -xc Local_MB -xl "Local Mem (MB)"                   \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    # Combine
    plotname=${plotdir}/all_$cfg.$PLOTEXT
    montage -tile 3x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi


# cleanup
rm -f ${TMP_FILE_PFX}*