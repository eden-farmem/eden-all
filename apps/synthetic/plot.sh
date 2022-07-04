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
TMP_FILE_PFX=tmp_syn_plot_

source ${ROOT_SCRIPTS_DIR}/utils.sh

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
        python3 ${ROOTDIR}/scripts/plot.py ${plots}   \
            -yc Xput -yl "Xput KOPS" --ymul 1e-3 ${YLIMS}   \
            -xc Local_MB -xl "Local Memo MB)"               \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    fi
    files="$files $plotname"

    #plot faults
    YLIMS="--ymin 0 --ymax 150"
    plotname=${plotdir}/rfaults_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}               \
            -yc "ReadPF" -yl "Read Faults KOPS" --ymul 1e-3 ${YLIMS}    \
            -xc Local_MB -xl "Local Mem (MB)"                           \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    fi
    files="$files $plotname"

    #plot faults
    plotname=${plotdir}/rafaults_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}               \
            -yc "ReadAPF" -yl "Read App Faults" --ymul 1e-3 ${YLIMS}     \
            -xc Local_MB -xl "Local Mem (MB)"                           \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    fi
    files="$files $plotname"

    # #plot faults
    # plotname=${plotdir}/wpfaults_${cfg}.${PLOTEXT}
    # if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
    #     python3 ${ROOTDIR}/scripts/plot.py ${plots}               \
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
            python3 ${ROOTDIR}/scripts/plot.py ${plots}   \
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
    # pattern="05-1[78]";    bkend=kona; zipfs=1;    tperc=100;  desc="noht"            ymax=500
    # pattern="05-1[89]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip5-noht"       ymax=300
    # pattern="05-1[89]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip50-noht"      ymax=75
    # pattern="05-1[89]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip500-noht"     ymax=10
    # pattern="06-0[23]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip-new-vdso"    ymax=1000
    # pattern="06-0[23]";    bkend=kona; zipfs=1;    tperc=100;  desc="zip5-new-vdso"   ymax=300
    # pattern="06-03";      bkend=kona; zipfs=1;    tperc=100;  desc="zip5-new-vdso2"   ymax=300
    # pattern="06-0\(6-22\|7\)"; bkend=kona; zipfs=1; tperc=100;  desc="zip-withpti"    ymax=500
    # pattern="06-07"         bkend=kona; zipfs=1;    tperc=100;  desc="zip5-withpti"     ymax=300

    cfg=be${bkend}_zs${zipfs}_tperc${tperc}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi
    # for cores in 1 2 3 4 5; do 
    for cores in 1; do 
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
        python3 ${ROOTDIR}/scripts/plot.py ${plots}         \
            -yc Xput -yl "Xput KOPS" --ymul 1e-3 ${YLIMS}   \
            -xc Local_MB -xl "Local Mem MB"                 \
            -l "1" -l ""                                    \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    fi
    files="$files $plotname"

    #plot faults
    YLIMS="--ymin 0 --ymax 200"
    plotname=${plotdir}/faults_$cfg.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}                 \
            -yc "ReadPF" -yl "Page Faults" --ymul 1e-3 ${YLIMS}     \
            -xc Local_MB -xl "Local Mem (MB)"                       \
            -l "" -l ""                                             \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    #plot speedup
    YLIMS="--ymin 1 --ymax 3"
    plotname=${plotdir}/speedup_$cfg.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${speedplots}        \
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


# performance of async page faults (vdso updates)
if [ "$PLOTID" == "4" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    speedplots=
    cmiopts=
    linestyles=
    files=
    LMEMCOL=6
    XPUTCOL=9
    ymax=300

    ## data
    # pattern="05-1[89]";   bkend=kona; zipfs=1;    tperc=100;  desc="zip5-noht";        ymax=300
    # pattern="06-0[23]";   bkend=kona; zipfs=1;    tperc=100;  desc="zip5-new-vdso";    ymax=300
    # pattern="06-03";      bkend=kona; zipfs=1;    tperc=100;  desc="zip5-new-vdso2";   ymax=300
    # pattern="06-07"       bkend=kona; zipfs=1;    tperc=100;  desc="zip5-withpti";     ymax=300

    cores=1
    bkend=kona; zipfs=1; tperc=100; 
    cfg=${cores}cores_zs${zipfs}_tperc${tperc}
    for kind in "kona" "original" "improved" "improved_nopti1" "improved_nopti2"; do 
        case $kind in
            "kona")             pattern="05-1[89]"; pgf=none;   desc="zip5-noht";;
            "original")         pattern="05-1[89]"; pgf=ASYNC;  desc="zip5-noht";;
            "improved")         pattern="06-07";    pgf=ASYNC;  desc="zip5-withpti";;
            "improved_nopti1")  pattern="06-0[23]"; pgf=ASYNC;  desc="zip5-new-vdso";;
            "improved_nopti2")  pattern="06-03";    pgf=ASYNC;  desc="zip5-new-vdso2";;
            *)                  echo "Unknown op"; exit;;
        esac
        if [[ $desc ]]; then descopt="-d=$desc"; fi

        cores=2
        datafile=$plotdir/data_${kind}_pgf${pgf}_${cfg}_${desc}
        if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
            bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgf \
                -c=$cores -of=$datafile -t=${thr} -zs=${zipfs} ${descopt}
        fi
        # cat $datafile | awk -F, '{ print $'$XPUTCOL' }' > ${TMP_FILE_PFX}_baseline_xput
        plots="$plots -d $datafile -l $kind"
        cat $datafile
    done

    # plot xput
    # YLIMS="--ymin 0 --ymax $ymax"
    plotname=${plotdir}/vdso_xput_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}         \
            -yc Xput -yl "Xput KOPS" --ymul 1e-3 ${YLIMS}   \
            -xc Local_MB -xl "Local Mem MB"                 \
            --size 5 3.5 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    #plot faults
    YLIMS="--ymin 0 --ymax 200"
    plotname=${plotdir}/vdso_faults_$cfg.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}                 \
            -yc "ReadPF" -yl "Page Faults" --ymul 1e-3 ${YLIMS}     \
            -xc Local_MB -xl "Local Mem (MB)"                       \
            --size 5 3.5 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    # Combine
    plotname=${plotdir}/vdso_improvements_$cfg.$PLOTEXT
    montage -tile 2x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi

# performance of async page faults (with multiple runs for each data point)
## FOR PAPER
if [ "$PLOTID" == "5" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    LMEMCOL=1
    XPUTCOL=2
    PLOTEXT=pdf

    ## data
    pattern="07-0[12]";   bkend=kona; zipfs=1; cores=4; tperc=100;  desc="zip5-moreruns"; ymax=600

    cfg=${cores}cores_be${bkend}_zs${zipfs}_tperc${tperc}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi
    thr=$((cores*tperc))

    pgf=none    #baseline
    basefile=$plotdir/data_${cores}cores_pgf${pgf}_${cfg}
    if [[ $FORCE ]] || [ ! -f "$basefile" ]; then
        echo "lmemfr,Xput,Faults,Backend,PFType,CPU,Threads,Zipfs" > $basefile
        for mem in `seq 1000 500 6000`; do 
            tmpfile=${TMP_FILE_PFX}data
            rm -f ${tmpfile}
            bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgf -lm=${mem} \
                -c=$cores -of=$tmpfile -t=${thr} -zs=${zipfs} ${descopt} --good
            cat $tmpfile
            memf=$(echo $mem | awk '{ printf "%.2f", $0/6000 }' )
            xmean=$(csv_column_mean $tmpfile "Xput")
            fmean=$(csv_column_mean $tmpfile "Faults")
            # NOTE: changing this ordering may require updating LMEMCOL, XPUTCOL, etc. 
            echo ${memf},${xmean},${fmean},${bkend},${pgf},${cores},${thr},${zipfs} >> ${basefile}
        done
    fi
    cat $basefile | awk -F, '{ print $'$XPUTCOL' }' > ${TMP_FILE_PFX}_baseline_xput
    cat $basefile

    pgf=ASYNC    #upcalls
    upcallfile=$plotdir/data_${cores}cores_pgf${pgf}_${cfg}
    if [[ $FORCE ]] || [ ! -f "$upcallfile" ]; then
        echo "lmemfr,Xput,Faults,Backend,PFType,CPU,Threads,Zipfs" > $upcallfile
        for mem in `seq 1000 500 6000`; do 
            tmpfile=${TMP_FILE_PFX}data
            rm -f ${tmpfile}
            bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgf -lm=${mem} \
                -c=$cores -of=$tmpfile -t=${thr} -zs=${zipfs} ${descopt} --good
            cat $tmpfile
            memf=$(echo $mem | awk '{ printf "%.2f", $0/6000 }' )
            xmean=$(csv_column_mean $tmpfile "Xput")
            fmean=$(csv_column_mean $tmpfile "Faults")
            # NOTE: changing this ordering may require updating LMEMCOL, XPUTCOL, etc. 
            echo ${memf},${xmean},${fmean},${bkend},${pgf},${cores},${thr},${zipfs} >> ${upcallfile}
        done
    fi
    cat $upcallfile | awk -F, '{ print $'$XPUTCOL' }' > ${TMP_FILE_PFX}_upcall_xput
    cat $upcallfile

    # speedup
    speedup=$plotdir/data_speedup_${cores}cores_${cfg}
    cat $basefile | awk -F, '{ print $'$LMEMCOL' }' > ${TMP_FILE_PFX}_lmem
    paste ${TMP_FILE_PFX}_baseline_xput ${TMP_FILE_PFX}_upcall_xput     \
        | awk  'BEGIN  { print "speedup" }; 
                NR>1   { if ($1 && $2)  print ($2-$1)*100/$1 
                        else            print ""    }' > ${TMP_FILE_PFX}_speedup
    paste -d, ${TMP_FILE_PFX}_lmem ${TMP_FILE_PFX}_speedup > ${speedup}
    speedplots="$speedplots -d ${speedup} -l $cores"
    cat $speedup

    # plot xput & speedup
    YLIMS="--ymin 0 --ymax $ymax"
    plotname=${plotdir}/xput_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}         \
            -dyc ${basefile} Xput -ls dashed -l "No Annot"  \
            -dyc ${upcallfile} Xput -ls solid -l "With Annot"   \
            -dyc ${speedup} speedup -ls dashdot -l "Speedup"    \
            -yl "KOPS" --ymul 1e-3 ${YLIMS}                 \
            --twin 3 -tyl "Gain (%)"                        \
            -xc lmemfr -xl "Local Memory Fraction"          \
            --size 5 3.5 -fs 13 -of $PLOTEXT -o $plotname
    fi
    display ${plotname} &

    #plot faults
    YLIMS="--ymin 0 --ymax 150"
    plotname=${plotdir}/faults_$cfg.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}             \
            -dyc ${basefile} Faults -ls dashed -l "No Annot"    \
            -dyc ${upcallfile} Faults -ls solid -l "With Annot" \
            -yl "KFPS" --ymul 1e-3 ${YLIMS}                     \
            -xc lmemfr -xl "Local Memory Fraction"              \
            --size 5 3.5 -fs 13 -of $PLOTEXT -o $plotname
    fi   
    display ${plotname} &
fi

# performance of async page faults with changing cores (with multiple runs for each data point)
## FOR PAPER
if [ "$PLOTID" == "6" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    CPUCOL=1
    XPUTCOL=2
    PLOTEXT=pdf
    speedplots=

    ## data
    pattern="05-1[89]";   bkend=kona; zipfs=1;    tperc=100;  desc="zip5-noht"; ymax=300

    cfg=be${bkend}_zs${zipfs}_tperc${tperc}_${desc}
    if [[ $desc ]]; then descopt="-d=$desc"; fi

    for mem in 1500 3000; do 
        pgf=none    #baseline
        basefile=$plotdir/data_lm${mem}_pgf${pgf}_${cfg}
        if [[ $FORCE ]] || [ ! -f "$basefile" ]; then
            echo "CPU,Xput,Faults,Backend,PFType,Threads,Zipfs,Local_MB" > $basefile
            for cores in `seq 1 1 10`; do 
                tmpfile=${TMP_FILE_PFX}data
                rm -f ${tmpfile}
                thr=$((cores*tperc))
                bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgf -lm=${mem} \
                    -c=$cores -of=$tmpfile -t=${thr} -zs=${zipfs} ${descopt} --good
                cat $tmpfile
                xmean=$(csv_column_mean $tmpfile "Xput")
                fmean=$(csv_column_mean $tmpfile "Faults")
                # NOTE: changing this ordering may require updating LMEMCOL, XPUTCOL, etc. 
                echo ${cores},${xmean},${fmean},${bkend},${pgf},${thr},${zipfs},${mem} >> ${basefile}
            done
        fi
        cat $basefile | awk -F, '{ print $'$XPUTCOL' }' > ${TMP_FILE_PFX}_baseline_xput
        cat $basefile

        pgf=ASYNC    #upcalls
        upcallfile=$plotdir/data_lm${mem}_pgf${pgf}_${cfg}
        if [[ $FORCE ]] || [ ! -f "$upcallfile" ]; then
            echo "CPU,Xput,Faults,Backend,PFType,Threads,Zipfs,Local_MB" > $upcallfile
            for cores in `seq 1 1 10`; do 
                tmpfile=${TMP_FILE_PFX}data
                rm -f ${tmpfile}
                thr=$((cores*tperc))
                bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgf -lm=${mem} \
                    -c=$cores -of=$tmpfile -t=${thr} -zs=${zipfs} ${descopt} --good
                cat $tmpfile
                xmean=$(csv_column_mean $tmpfile "Xput")
                fmean=$(csv_column_mean $tmpfile "Faults")
                # NOTE: changing this ordering may require updating LMEMCOL, XPUTCOL, etc. 
                echo ${cores},${xmean},${fmean},${bkend},${pgf},${thr},${zipfs},${mem} >> ${upcallfile}
            done
        fi
        cat $upcallfile | awk -F, '{ print $'$XPUTCOL' }' > ${TMP_FILE_PFX}_upcall_xput
        cat $upcallfile

        # speedup
        speedup=$plotdir/data_speedup_lm${mem}_${cfg}
        cat $basefile | awk -F, '{ print $'$CPUCOL' }' > ${TMP_FILE_PFX}_cpu
        paste ${TMP_FILE_PFX}_baseline_xput ${TMP_FILE_PFX}_upcall_xput     \
            | awk  'BEGIN  { print "speedup" }; 
                    NR>1   { if ($1 && $2)  print ($2-$1)*100/$1 
                            else            print ""    }' > ${TMP_FILE_PFX}_speedup
        paste -d, ${TMP_FILE_PFX}_cpu ${TMP_FILE_PFX}_speedup > ${speedup}
        memf=$(echo $mem | awk '{ printf "%d", $0*100/6000 }' )
        speedplots="$speedplots -d ${speedup} -l $memf%"
        cat $speedup
    done

    # plot speedup
    plotname=${plotdir}/speedup_${cfg}.${PLOTEXT}
    echo $speedplots
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${speedplots}    \
            -yc speedup -yl "Gain (%)" --ymin 0 --ymax 100  \
            -xc CPU -xl "CPU Cores"                         \
            --size 5 3.5 -fs 13 -of $PLOTEXT -o $plotname -lt "Local Memory"
    fi
    display ${plotname} &

    # #plot faults
    # YLIMS="--ymin 0 --ymax 150"
    # plotname=${plotdir}/faults_$cfg.${PLOTEXT}
    # if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
    #     python3 ${ROOTDIR}/scripts/plot.py ${plots}             \
    #         -dyc ${basefile} Faults -ls dashed -l "No Annot"    \
    #         -dyc ${upcallfile} Faults -ls solid -l "With Annot" \
    #         -yl "KFPS" --ymul 1e-3 ${YLIMS}                     \
    #         -xc lmemfr -xl "Local Memory Fraction"              \
    #         --size 5 3.5 -fs 13 -of $PLOTEXT -o $plotname
    # fi   
    # display ${plotname} &
fi

# cleanup
rm -f ${TMP_FILE_PFX}*