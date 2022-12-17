#!/bin/bash
# set -e

# PSort plots

PLOTEXT=pdf
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
    for runcfg in "fswap7" "eden"; do
        LABEL=
        LS=
        CMI=

        case $runcfg in
        # "fswap")        pattern="12-10"; rmem=fastswap; backend=rdma; cores=10; tperc=1; rdhd=0; desc="fshero"; LS=solid; CMI=1; LABEL="Fastswap";;
        "fswap7")       pattern="12-1[03]"; rmem=fastswap; backend=rdma; cores=10; tperc=1; rdhd=7; desc="fshero"; LS=solid; CMI=1; LABEL="Fastswap";;
        "eden")         pattern="12-12"; rmem=eden; backend=rdma; cores=10; tperc=1; rdhd=63; desc="hero";  LS=solid; CMI=1; LABEL="Eden";;
        *)              echo "Unknown config"; exit;;
        esac

        # filter results
        cfg=be${bkend}_cores${cores}_tperc${tperc}
        label=$runcfg
        datafile=$plotdir/data_${LABEL}
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
            echo "LMem%,Time,TimeErr,Faults,FaultsErr,HitR,Count,System,Backend,EvP,EvB,CPU,Zipfs" > $datafile
            for memp in `seq 10 15 100`; do
                tmpfile=${TMP_FILE_PFX}data
                rm -f ${tmpfile}
                echo bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -c=$cores \
                    -t=${thr} -be=${bkend} ${descopt} ${evbopt} ${rmemopt} ${evpopt} ${rdopt} -lmp=${memp}
                bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -c=$cores -of=$tmpfile  \
                    -t=${thr} -be=${bkend} ${descopt} ${evbopt} ${rmemopt} ${evpopt} ${rdopt} -lmp=${memp}
                cat $tmpfile
                tmean=$(csv_column_mean $tmpfile "Time(s)")
                tstd=$(csv_column_stdev $tmpfile "Time(s)")
                xnum=$(csv_column_count $tmpfile "Time(s)")
                fmean=$(csv_column_mean $tmpfile "PF")
                fstd=$(csv_column_stdev $tmpfile "PF")
                echo ${memp},${tmean},${tstd},${fmean},${fstd},${hitrmean},${xnum},${rmem},${bkend},${evp},${evb},${cores},${zipfs} >> ${datafile}
            done

            # compute and add normalized throughput column
            baseline=
            case $rmem in
            "fastswap")         baseline=65;;
            "eden")             baseline=57;;
            *)                  echo "Unknown rmem"; exit;;
            esac
            timenorm=$(csv_column "$datafile" "Time" | awk '{ if($1) printf "%lf\n", ($1/'$baseline'); else print ""; }')
            timenormerr=$(csv_column "$datafile" "TimeErr" | awk '{ if($1) printf "%lf\n", ($1/'$baseline'); else print ""; }')
            echo -e "TimeNorm\n${timenorm}" > ${TMP_FILE_PFX}normtime
            echo -e "TimeErrNorm\n${timeerrnorm}" > ${TMP_FILE_PFX}normtimeerr
            paste -d, $datafile ${TMP_FILE_PFX}normtime ${TMP_FILE_PFX}normtimeerr > ${TMP_FILE_PFX}normdata
            mv ${TMP_FILE_PFX}normdata $datafile
        fi

        label=${LABEL:-$runcfg}
        ls=${LS:-solid}
        cmi=${CMI:-1}
        plots="$plots -d $datafile -l $label -ls $ls -cmi $cmi"
        cat $datafile
    done

    #plot time
    plotname=${plotdir}/sort_overhead.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}     \
            -yce "TimeNorm" "TimeErrNorm" -yl "Normalized Runtime"           \
            -xc "LMem%" -xl "Local Memory (%)"          \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    # #plot total faults
    YLIMS="--ymin 0 --ymax 10"
    plotname=${plotdir}/sort_faults.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}                     \
            -yce "Faults" "FaultsErr" -yl "Faults (Millions)" --ymul 1e-6 ${YLIMS}       \
            -xc "LMem%" -xl "Local Memory (%)"                          \
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

# cleanup
rm -f ${TMP_FILE_PFX}*