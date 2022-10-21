#!/bin/bash
set -e
set +x

#
# Benchmarking Kona's page fault bandwidth
# in various configurations
# 

usage="\n
-f, --force \t\t force re-run experiments\n
-l, --lat \t\t get latencies\n
-p, --plot \t\t generate plot from results\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
TEMP_PFX=tmp_kona_
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=plots 
DATADIR=data
PLOTEXT=png
CFGFILE=${TEMP_PFX}shenango.config
LATFILE=latencies

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="-DDEBUG $CFLAGS"
    ;;

    -f|--force)
    FORCE=1
    ;;
    
    -l|--lat)
    LATENCIES=1
    OPTS="$OPTS --lat"
    ;;
    
    -p|--plot)
    PLOT=1
    ;;

    -h | --help)
    echo -e $usage
    exit
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# run
set +e    #to continue to cleanup even on failure
mkdir -p $DATADIR
CFLAGS_BEFORE=$CFLAGS
OPTS_BEFORE=$OPTS
NHANDLERS=1

set_hints_opts() {
    rmem=$1
    case $rmem in
    "normem")           ;;
    "nohints")          LS=dotted;      OPTS="$OPTS --rmem";;
    "hints")            LS=solid;       OPTS="$OPTS --rmem --hints";;
    "hints+1")          LS=dashed;      OPTS="$OPTS --rmem --hints --rdahead=1";;
    "hints+2")          LS=dashdot;     OPTS="$OPTS --rmem --hints --rdahead=2";;
    "hints+4")          LS=dashdotdot;  OPTS="$OPTS --rmem --hints --rdahead=4";;
    *)                  echo "Unknown rmem type"; exit;;
    esac
}

set_evict_opts() {
    evict=$1
    case $evict in
    "noevict")          ;;
    "evict")            OPTS="$OPTS --evict";;
    *)                  echo "Unknown evict type"; exit;;
    esac
}

set_backend_opts() {
    bkend=$1
    case $bkend in
    "none")             ;;
    "local")            OPTS="$OPTS --bkend=local"; LS=dashed;  CMI=0;;
    "rdma")             OPTS="$OPTS --bkend=rdma";  LS=solid;   CMI=1;;
    *)                  echo "Unknown backend type"; exit;;
    esac
}

set_fault_op_opts() {
    op=$1
    case $op in
    "read")             CFLAGS="-DFAULT_OP=0 $CFLAGS";;
    "write")            CFLAGS="-DFAULT_OP=1 $CFLAGS ";;
    "r+w")              CFLAGS="-DFAULT_OP=2 $CFLAGS ";;
    "random")           CFLAGS="-DFAULT_OP=3 $CFLAGS ";;
    *)                  echo "Unknown fault op"; exit;;
    esac
}

measure_xput()
{
    for bkend in "local" "rdma"; do
        for rmem in "hints"; do     #"hints+1" "hints+2" "hints+4"; do
            for evict in "evict"; do
                for op in "read"; do
                    # reset
                    cfg=${rmem}-${evict}-${bkend}-${op}
                    CFLAGS=${CFLAGS_BEFORE}
                    OPTS=${OPTS_BEFORE}
                    LS=solid
                    CMI=1

                    # set opts
                    set_hints_opts      "$rmem"
                    set_evict_opts      "$evict"
                    set_backend_opts    "$bkend"
                    set_fault_op_opts   "$op"

                    # run and log result
                    datafile=$DATADIR/xput-${cfg}
                    if [ ! -f $datafile ] || [[ $FORCE ]]; then
                        bash run.sh --clean
                        bash run.sh ${OPTS} -fl="""$CFLAGS""" --force --buildonly   #recompile
                        echo "cores,xput" > $datafile
                        for cores in `seq 1 1 12`; do 
                        # for cores in 1; do 
                            rm -f result
                            bash run.sh ${OPTS} -t=${cores} -fl="""$CFLAGS"""
                            xput=$(cat result 2>/dev/null)
                            echo "$cores,$xput" >> $datafile        # record xput

                            # clean and wait a bit
                            bash run.sh --clean
                            sleep 10
                        done
                    fi
                    cat $datafile
                    plots="$plots -d $datafile -l ${rmem}-${bkend} -ls $LS -cmi $CMI"
                done
            done
        done
    done

    if [[ $PLOT ]]; then
        mkdir -p ${PLOTDIR}
        plotname=${PLOTDIR}/fault_xput.${PLOTEXT}
        python ${PLOTSRC} ${plots}                  \
            -xc cores -xl "App CPU"                 \
            -yc xput -yl "MOPS" --ymul 1e-6         \
            --ymin 0 --ymax 1.75                    \
            --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname
        display $plotname &
    fi
}

measure_latency()
{
    for rmem in "hints" "hints+1" "hints+2" "hints+4"; do
    # for rmem in "hints"; do
        for evict in "noevict"; do
        # for evict in "noevict" "evict"; do
            for bkend in "local" "rdma"; do
                for op in "read"; do
                    # reset
                    cfg=${rmem}-${evict}-${bkend}-${op}
                    CFLAGS=${CFLAGS_BEFORE}
                    OPTS=${OPTS_BEFORE}
                    LS=solid
                    CMI=1

                    # set opts
                    set_hints_opts      "$rmem"
                    set_evict_opts      "$evict"
                    set_backend_opts    "$bkend"
                    set_fault_op_opts   "$op"

                    # run and log result
                    latfile=$DATADIR/lat-${cfg}
                    if [ ! -f "$latfile" ] || [[ $FORCE ]]; then
                        bash run.sh --clean
                        bash run.sh ${OPTS} -fl="""$CFLAGS""" --force --buildonly   #recompile
                        for cores in 1; do 
                            rm -f result
                            bash run.sh ${OPTS} -t=${cores} -fl="""$CFLAGS"""
                            xput=$(cat result 2>/dev/null)
                            echo "RESULT: $xput"
                            if [ ! -f $LATFILE ]; then 
                                echo "no latency file ${LATFILE} found"
                                exit 1
                            fi
                            mv -f ${LATFILE} ${latfile}

                            # clean and wait a bit
                            bash run.sh --clean
                            echo "waiting 10 secs"
                            sleep 10
                        done
                    fi
                    latplots="$latplots -d ${latfile} -l ${rmem}-${evict}-${bkend} -ls $LS -cmi $CMI"
                done
            done
        done
    done

    if [[ $PLOT ]]; then
        mkdir -p $PLOTDIR
        echo $latplots
        plotname=${PLOTDIR}/latency.${PLOTEXT}
        python3 ${PLOTSRC} -z cdf ${latplots}       \
            -yc latency -xl "Latency (µs)" -yl "CDF"\
            --xmin 0 --xmax 40 -nm --xmul 1e-3      \
            --size 6 3.5 -fs 12 -of ${PLOTEXT} -o $plotname 
        display $plotname & 
    fi
}

if [[ $LATENCIES ]]; then
    measure_latency
else
    measure_xput
fi

# cleanup
rm -f ${TEMP_PFX}*
