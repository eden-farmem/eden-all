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
    NORMALIZE=
    CORES=5

    ## data
    # for runcfg in "no-rdahead" "rdahead"; do 
    # for runcfg in "evbatch-1" "evbatch-8"; do 
    # for runcfg in "evbatch12-1" "evbatch12-8" "evbatch12-16"; do 
    # for runcfg in "tpc-1" "tpc-5"; do 
    for runcfg in "evp-none" "evp-sc"; do 
    # for runcfg in "eden-local" "fswap-local"; do
    # for runcfg in "fswap" "eden-bh" "eden-evb" "eden" "eden-rd"; do

        case $runcfg in
        "no-rdahead")       pattern="11-16-11-[34]"; backend=local; cores=5; zipfs=1; tperc=1; desc="rdahead";;
        "rdahead")          pattern="11-16-11-[12]"; backend=local; cores=5; zipfs=1; tperc=1; desc="rdahead";;
        "evbatch-1")        pattern="11-16-11-[34]"; backend=local; cores=5; zipfs=1; tperc=1; desc="rdahead";;
        "evbatch-8")        pattern="11-16-12";      backend=local; cores=5; zipfs=1; tperc=1; desc="evbatch";;
        "evbatch12-1")      pattern="11-\(25-23\|26-00\)"; backend=local; cores=12; zipfs=1; tperc=1; evb=1;  desc="12cores";;
        "evbatch12-8")      pattern="11-\(25-23\|26-00\)"; backend=local; cores=12; zipfs=1; tperc=1; evb=8;  desc="12cores";;
        "evbatch12-16")     pattern="11-\(25-23\|26-00\)"; backend=local; cores=12; zipfs=1; tperc=1; evb=16; desc="12cores";;
        "tpc-1")            pattern="11-16-\(09\|10\)"; backend=rdma; cores=5; zipfs=1; tperc=1; desc="nowaitsteals";;
        "tpc-5")            pattern="11-16-\(09\|10\)"; backend=rdma; cores=5; zipfs=1; tperc=5; desc="nowaitsteals";;
        "evp-none")         pattern="11-29-1[78]"; backend=local; cores=5; zipfs=1; tperc=1; evp=NONE; desc="hitratio";;
        "evp-sc")           pattern="11-29-1[78]"; backend=local; cores=5; zipfs=1; tperc=1; evp=SC; desc="hitratio";;
        "evp-lru")          pattern="11-29-1[78]"; backend=local; cores=5; zipfs=1; tperc=1; evp=LRU; desc="hitratio";;
        "eden-local")       pattern="11-16-11-[34]"; backend=local; cores=5; zipfs=1; tperc=1; desc="rdahead";;
        "fswap-local")      pattern="11-26-14"; rmem=fastswap; backend=local; cores=5; zipfs=1; tperc=1; desc="nordahead";;
        "fswap")            pattern="11-26-1"; rmem=fastswap; backend=rdma; cores=${CORES}; zipfs=1; tperc=5; desc="nordahead";;
        "eden-bh")          pattern="11-28-1[4-8]"; rmem=eden-bh; backend=local; cores=${CORES}; zipfs=1; tperc=5; evb=1; rdhd=no; desc="incremental";;
        "eden-evb")         pattern="11-28-1[4-8]"; rmem=eden-bh; backend=local; cores=${CORES}; zipfs=1; tperc=5; evb=8; rdhd=no; desc="incremental";;
        "eden")             pattern="11-28-1[4-8]"; rmem=eden; backend=local; cores=${CORES}; zipfs=1; tperc=5; evb=8; evp=NONE; rdhd=no; desc="incremental";;
        "eden-rd")          pattern="11-28-1[4-8]"; rmem=eden; backend=local; cores=${CORES}; zipfs=1; tperc=5; evb=8; evp=NONE; rdhd=yes; desc="incremental";;
        "eden-sc")          pattern="11-28-1[4-8]"; rmem=eden; backend=local; cores=${CORES}; zipfs=1; tperc=5; evb=8; evp=SC; rdhd=yes; desc="incremental";;
        "eden-lru")         pattern="11-28-2[12]"; rmem=eden; backend=local; cores=${CORES}; zipfs=1; tperc=5; evb=8; evp=LRU; rdhd=yes; desc="incremental";;
        *)                  echo "Unknown config"; exit;;
        esac

        # filter results
        cfg=be${bkend}_cores${cores}_zs${zipfs}_tperc${tperc}
        label=$runcfg
        datafile=$plotdir/data_${cfg}_${runcfg}
        thr=$((cores*tperc))
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
        if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
            bash ${SCRIPT_DIR}/show.sh -cs="$pattern" -be=$backend -c=$cores -of=$datafile  \
                -t=${thr} -zs=${zipfs} -be=${bkend} ${descopt} ${evbopt} ${rmemopt} ${evpopt} ${rdopt}
        fi

        # compute and add normalized throughput column
        if [[ $NORMALIZE ]]; then
            maxput=$(csv_column_max "$datafile" "Xput")
            echo $maxput
            xputnorm=$(csv_column "$datafile" "Xput" | awk '{ if($1) print $1/'$maxput'; else print ""; }')
            echo -e "XputNorm\n${xputnorm}" > ${TMP_FILE_PFX}normxput
            paste -d, $datafile ${TMP_FILE_PFX}normxput > ${TMP_FILE_PFX}normdata
            mv ${TMP_FILE_PFX}normdata $datafile
        fi

        plots="$plots -d $datafile -l $label"
        cat $datafile
    done

    #plot xput
    XPUTCOL="Xput"
    YLIMS="--ymin 0 --ymax $((50+150*cores))"
    YLABEL="Xput KOPS"
    YMUL="--ymul 1e-3"
    if [[ $NORMALIZE ]]; then
        XPUTCOL="XputNorm"
        YLIMS="--ymin 0 --ymax 1.2"
        YLABEL="Normalized Xput"
        YMUL=
    fi
    plotname=${plotdir}/xput_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}             \
            -yc ${XPUTCOL} -yl "${YLABEL}" ${YMUL} ${YLIMS}     \
            -xc "LMem%" -xl "Local Mem (%)"                     \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    #plot faults
    YLIMS="--ymin 0 --ymax $((100*cores))"
    plotname=${plotdir}/rfaults_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}                     \
            -yc "Faults" -yl "Faults KOPS" --ymul 1e-3 ${YLIMS}         \
            -xc "LMem%" -xl "Local Mem (%)"                             \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

    # Hit ratio
    YLIMS="--ymin 0 --ymax 100"
    plotname=${plotdir}/hitr_${cfg}.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOTDIR}/scripts/plot.py ${plots}                     \
            -yc "HitR" -yl "Hit Ratio %" ${YLIMS}                       \
            -xc "LMem%" -xl "Local Mem (%)"                             \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname
    fi
    files="$files $plotname"

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