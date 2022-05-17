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
    if [[ $7 ]]; then labelopt="-l $7"; fi
    if [[ $8 ]]; then cmiopt="-cmi $8"; fi
    if [[ $9 ]]; then lsopt="-ls $9";   fi

    datafile=$plotdir/data_${cores}cores_be${backend}_pgf${pgfaults}_zs${zparams}_tperc${tperc}
    thr=$((cores*tperc))
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -pf=$pgfaults \
            -c=$cores -of=$datafile -t=${thr} -zs=${zparams}
    fi
    plots="$plots -d $datafile $labelopt $cmiopt $lsopt"
    cat $datafile
}

# performance with kona/page faults
if [ "$PLOTID" == "1" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=

    cfg=be${backend}_pgf${pgfaults}_zs${zs}_tperc${tperc}
    for cores in 1 2 3 4 5; do
        label=$cores
        # add_plot_group  pattern                                   bkend pgf   zs tperc cores  label
        # add_plot_group "05-\(09-23\|10-0[01234]\|10-05-[012]\)"   kona none   0.1 1   $cores  $label
        # add_plot_group "05-\(09-23\|10-0[01234]\|10-05-[012]\)"   kona SYNC   0.1 1   $cores  $label
        # add_plot_group "05-\(09-23\|10-0[01234]\|10-05-[012]\)"   kona ASYNC  0.1 1   $cores  $label
        # add_plot_group "05-10-\(09\|10\)"                         kona ASYNC  0.1 10  $cores  $label
        # add_plot_group "05-10-\(09\|1\)"                          kona ASYNC  0.1 60  $cores  $label
        # add_plot_group "05-11"                                    kona ASYNC  0.1 60  $cores  $label
        # add_plot_group "05-11"                                    kona ASYNC  0.1 110 $cores  $label
        # add_plot_group "05-11"                                    kona ASYNC  0.1 160 $cores  $label
        # add_plot_group "05-11"                                    kona ASYNC  0.1 210 $cores  $label
        # add_plot_group "05-\(11-23\|12\)"                         kona none   0.5 100 $cores  $label
        # add_plot_group "05-\(11-23\|12\)"                         kona ASYNC  0.5 100 $cores  $label
        # add_plot_group "05-\(11-23\|12\)"                         kona none   1   100 $cores  $label
        add_plot_group "05-\(11-23\|12\)"                           kona ASYNC  1   100 $cores $label
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

# performance with kona/page faults with baseline
if [ "$PLOTID" == "3" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    files=
    plots=

    for cores in 1 2; do 
        cfg=${cores}cores
        label=$cores
        # add_plot_group  pattern                                   bkend pgf   zs tperc cores  label   cmi style
        # add_plot_group "05-\(09-23\|10-0[01234]\|10-05-[012]\)"   kona none   0.1 1   $cores  "kona"    0 dashed
        # add_plot_group "05-\(09-23\|10-0[01234]\|10-05-[012]\)"   kona ASYNC  0.1 1   $cores  "async"   1 solid
        add_plot_group "05-\(11-23\|12\)"                           kona none   1   100 $cores  $label  0   dashed
        add_plot_group "05-\(11-23\|12\)"                           kona ASYNC  1   100 $cores  $label  1   solid
    done

    # plot xput
    YLIMS="--ymin 0 --ymax 1000"
    plotname=${plotdir}/xput.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py ${plots}   \
            -yc Xput -yl "Xput KOPS" --ymul 1e-3 ${YLIMS}   \
            -xc Local_MB -xl "Local Memo MB)"               \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    #plot faults
    YLIMS="--ymin 0 --ymax 200"
    plotname=${plotdir}/rfaults_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py ${plots}               \
            -yc "ReadPF" -yl "Read App Faults" --ymul 1e-3 ${YLIMS}    \
            -xc Local_MB -xl "Local Mem (MB)"                           \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU"
    fi
    files="$files $plotname"

    # Combine
    plotname=${plotdir}/all.$PLOTEXT
    montage -tile 3x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi


# cleanup
rm -f ${TMP_FILE_PFX}*