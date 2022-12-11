#!/bin/bash
# set -e

# PSort plots

PLOTEXT=png
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
PLOTDIR=${SCRIPT_DIR}/plots
DATADIR=${SCRIPT_DIR}/data
TMP_FILE_PFX=tmp_psort_plot_

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


# performance with kona/page faults
if [ "$PLOTID" == "1" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=
    NORMALIZE=1
    CORES=5

    ## data
    for runcfg in "fswap" "fswap7"; do
        case $runcfg in
        "fswap")        pattern="12-10"; rmem=fastswap; backend=rdma; cores=10; tperc=1; rdhd=0; desc="fshero";;
        "fswap7")       pattern="12-10"; rmem=fastswap; backend=rdma; cores=10; tperc=1; rdhd=7; desc="fshero";;
        *)              echo "Unknown config"; exit;;
        esac

        # filter results
        cfg=be${bkend}_cores${cores}_tperc${tperc}
        label=$runcfg
        datafile=$plotdir/data_${runcfg}_${cores}cpu
        thr=$((cores*tperc))
        descopt=
        evbopt=
        rmemopt=
        rdopt=
        if [[ $desc ]]; then descopt="-d=$desc";    fi
        if [[ $evb ]];  then evbopt="-evb=$evb";    fi
        if [[ $evp ]];  then evpopt="-evp=$evp";    fi
        if [[ $rmem ]];  then rmemopt="-r=$rmem";   fi
        if [[ $rdhd ]];  then rdopt="-rd=$rdhd";    fi
        if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
            bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -c=$cores -of=$datafile  \
                -t=${thr} -be=${bkend} ${descopt} ${evbopt} ${rmemopt} ${evpopt} ${rdopt}
        fi

        # compute and add normalized throughput column
        if [[ $NORMALIZE ]]; then
            baseline=
            case $rmem in
            "fastswap")         baseline=65;;
            "eden")             baseline=;;
            "eden-bh")          baseline=;;
            *)                  echo "Unknown rmem"; exit;;
            esac
            overhead=$(csv_column "$datafile" "Time(s)" \
                | awk '{ if($1) printf "%lf\n", ($1-'$baseline')*100/'$baseline'; else print ""; }')
            echo -e "Overhead\n${overhead}" > ${TMP_FILE_PFX}overhead
            paste -d, $datafile ${TMP_FILE_PFX}overhead > ${TMP_FILE_PFX}withoverhead
            mv ${TMP_FILE_PFX}withoverhead $datafile
        fi

        plots="$plots -d $datafile -l $label"
        cat $datafile
    done

    #plot xput
    plotname=${plotdir}/overhead_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}     \
            -yc "Overhead" -yl "Overhead (%)"           \
            -xc "LMem%" -xl "Local Mem (%)"             \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    # #plot total faults
    YLIMS="--ymin 0 --ymax 25"
    plotname=${plotdir}/rfaults_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}                     \
            -yc "PF" -yl "Faults (Millions)" --ymul 1e-6 ${YLIMS}       \
            -xc "LMem%" -xl "Local Mem (%)"                             \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    # # Hit ratio
    # YLIMS="--ymin 0 --ymax 100"
    # plotname=${plotdir}/hitr_${cfg}.${PLOTEXT}
    # if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
    #     python3 ${ROOTDIR}/scripts/plot.py ${plots}                     \
    #         -yc "HitR" -yl "Hit Ratio %" ${YLIMS}                       \
    #         -xc "LMem%" -xl "Local Mem (%)"                             \
    #         --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    # fi
    # files="$files $plotname"

    # Combine
    plotname=${plotdir}/${cfg}.$PLOTEXT
    montage -tile 3x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi

# performance with no faults
if [ "$PLOTID" == "2" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plotname=${plotdir}/nofaults.${PLOTEXT}
    YLIMS="--ymin 0 --ymax 1000"
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py  -z bar --xstr               \
            -d ${DATADIR}/xput_nofaults_sc30    -l "Eden-Machine"       \
            -d ${DATADIR}/xput_nofaults_sc40    -l "Fswap-Machine"      \
            -yce "xput" "error" -yl "KOPS" -ym 1e-3 ${YLIMS}            \
            -xc "system" -xl " " --xstr                                 \
            --size 5 5 -fs 12 -of $PLOTEXT -o $plotname
    fi
    display ${plotname} &
fi

# cleanup
rm -f ${TMP_FILE_PFX}*