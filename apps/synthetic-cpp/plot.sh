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
        --size 6 3 -of $PLOTEXT -o $plotname -fs 11 --ylog
    echo "saved plot to $plotname"
    # display $plotname &
fi

# Paper grade plots
if [ "$PLOTID" == "2" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=
    files=
    NORMALIZE=1
    CORES=10

    ## data
    for runcfg in "noprio" "prio" "noprio+sc" "prio+sc" "prio+sc+bh" "prio+sc+bh+init"; do
        LABEL=
        LS=
        CMI=

        case $runcfg in
        "noprio")               pattern="04-07"; rmem=eden; backend=rdma; cores=${CORES}; evb=32; evp=NONE; evprio=no; desc="rdma"; LS=dashed; CMI=0; LABEL="No-Prio";;
        "prio")                 pattern="04-07"; rmem=eden; backend=rdma; cores=${CORES}; evb=32; evp=NONE; evprio=yes; desc="rdma"; LS=solid; CMI=1; LABEL="Prio";;
        "noprio+sc")            pattern="04-07"; rmem=eden; backend=rdma; cores=${CORES}; evb=32; evp=SC; evprio=no; desc="rdma"; LS=dashed; CMI=0; LABEL="No-Prio(SC)";;
        "prio+sc")              pattern="04-07"; rmem=eden; backend=rdma; cores=${CORES}; evb=32; evp=SC; evprio=yes; desc="rdma"; LS=solid; CMI=1; LABEL="Prio(SC)";;
        "prio+sc+bh")           pattern="04-07"; rmem=eden-bh; backend=rdma; cores=${CORES}; evb=32; evp=SC; evprio=yes; desc="rdma"; LS=solid; CMI=1; LABEL="Prio(SC+BH)";;
        "prio+sc+bh+init")      pattern="04-07"; rmem=eden; backend=rdma; cores=${CORES}; evb=32; evp=SC; evprio=yes; desc="rdma-noinit"; LS=solid; CMI=1; LABEL="Prio(SC+NoInit)";;
        *)                      echo "Unknown config"; exit;;
        esac

        # filter results
        label=$runcfg
        datafile=$plotdir/data_${LABEL}
        descopt=
        evbopt=
        rmemopt=
        evpopt=
        rdopt=
        if [[ $desc ]]; then descopt="-d=$desc";    fi
        if [[ $evb ]];  then evbopt="-evb=$evb";    fi
        if [[ $evp ]];  then evpopt="-evp=$evp";    fi
        if [[ $rmem ]];  then rmemopt="-r=$rmem";   fi
        if [[ $rdhd ]];  then rdopt="-rd=$rdhd";    fi
        if [[ $evprio ]];  then evpropt="-evpr=$evprio";    fi

        if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
            echo "LMem%,Xput,XputErr,Faults,FaultsErr,NetReads,NetReadsErr,HitR,Count,System,Backend,EvP,EvB,CPU,Zipfs" > $datafile
            for memp in 100 91 83 75 66 58 50 41 33 22 16 8 4; do
                tmpfile=${TMP_FILE_PFX}data
                rm -f ${tmpfile}
                echo bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -c=$cores -of=$tmpfile  \
                    -be=${bkend} ${descopt} ${evbopt} ${rmemopt} ${evpopt} ${rdopt} ${evpropt} -lmp=${memp}
                bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -c=$cores -of=$tmpfile  \
                    -be=${bkend} ${descopt} ${evbopt} ${rmemopt} ${evpopt} ${rdopt} ${evpropt} -lmp=${memp}
                cat $tmpfile
                xmean=$(csv_column_mean $tmpfile "Xput")
                xstd=$(csv_column_stdev $tmpfile "Xput")
                xnum=$(csv_column_count $tmpfile "Xput")
                fmean=$(csv_column_mean $tmpfile "Faults")
                fstd=$(csv_column_stdev $tmpfile "Faults")
                nrmean=$(csv_column_mean $tmpfile "NetReads")
                nrstd=$(csv_column_stdev $tmpfile "NetReads")
                hitrmean=$(csv_column_mean $tmpfile "HitR")
                echo ${memp},${xmean},${xstd},${fmean},${fstd},${nrmean},${nrerr},${hitrmean},${xnum},${rmem},${bkend},${evp},${evb},${cores},${zipfs} >> ${datafile}
            done

            # compute and add normalized throughput column
            maxput=$(csv_column_max "$datafile" "Xput")
            echo $maxput
            xputnorm=$(csv_column "$datafile" "Xput" | awk '{ if($1) print $1/'$maxput'; else print ""; }')
            xputerrnorm=$(csv_column "$datafile" "XputErr" | awk '{ if($1) print $1/'$maxput'; else print ""; }')
            echo -e "XputNorm\n${xputnorm}" > ${TMP_FILE_PFX}normxput
            echo -e "XputErrNorm\n${xputerrnorm}" > ${TMP_FILE_PFX}normxputerr
            paste -d, $datafile ${TMP_FILE_PFX}normxput ${TMP_FILE_PFX}normxputerr > ${TMP_FILE_PFX}normdata
            mv ${TMP_FILE_PFX}normdata $datafile
        fi

        label=${LABEL:-$runcfg}
        ls=${LS:-solid}
        cmi=${CMI:-1}
        plots="$plots -d $datafile -l $label -ls $ls -cmi $cmi"
        cat $datafile
    done

    #plot xput
    XPUTCOL="Xput"
    XPUTERR="XputErr"
    YLIMS="--ymin 0 --ymax 600"
    YLABEL="KOPS"
    YMUL="--ymul 1e-3"
    XLIMS="--xmin 0 --xmax 110"
    if [[ $NORMALIZE ]]; then
        XPUTCOL="XputNorm"
        XPUTERR="XputErrNorm"
        YLIMS="--ymin 0 --ymax 1.1"
        YLABEL="Normalized Throughput"
        YMUL=
    fi
    plotname=${plotdir}/synthetic_prio_xput.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}             \
            -yce ${XPUTCOL} ${XPUTERR} -yl "${YLABEL}" ${YMUL} ${YLIMS}     \
            -xc "LMem%" -xl "Local Mem (%)"                     \
            --size 4.5 3 -fs 10 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    #plot faults
    YLIMS="--ymin 0 --ymax 850"
    plotname=${plotdir}/synthetic_netreads.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}                     \
            -yce "NetReads" "NetReadsErr" -yl "Remote Page Fetches(KOPS)" --ymul 1e-3 ${YLIMS}   \
            -xc "LMem%" -xl "Local Mem (%)" ${XLIMS}                    \
            --size 4.5 3 -fs 10 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    # ## Hit ratio
    # YLIMS="--ymin 0 --ymax 100"
    # plotname=${plotdir}/synthetic_hitrate.${PLOTEXT}
    # if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
    #     python3 ${ROOTDIR}/scripts/plot.py ${plots}                     \
    #         -yc "HitR" -yl "Hit Ratio %" ${YLIMS}                       \
    #         -xc "LMem%" -xl "Local Mem (%)"                             \
    #         --size 4.5 3 -fs 10 -of $PLOTEXT -o $plotname
    # fi
    # files="$files $plotname"

    # Combine
    plotname=${plotdir}/${cfg}.$PLOTEXT
    montage -tile 3x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi


# cleanup
rm -f ${TMP_FILE_PFX}*