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
-t, --test \t\t run all configs once for testing\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
ROOT_DIR="${SCRIPT_DIR}/../.."
ROOT_SCRIPTS_DIR="${ROOT_DIR}/scripts/"
TEMP_PFX=tmp_shenango_
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=plots 
DATADIR=data
PLOTEXT=png
CFGFILE=${TEMP_PFX}shenango.config
LATFILE=latencies
# PRELOAD="--preload"

source ${ROOT_SCRIPTS_DIR}/utils.sh

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

    -t|--test)
    TEST=1
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
    "bhints")           LS=solid;       OPTS="$OPTS --rmem --bhints";;
    "hints")            LS=solid;       OPTS="$OPTS --rmem --hints";;
    "hints+1")          LS=dashed;      OPTS="$OPTS --rmem --hints --rdahead=1";;
    "hints+2")          LS=dashdot;     OPTS="$OPTS --rmem --hints --rdahead=2";;
    "hints+4")          LS=dashdotdot;  OPTS="$OPTS --rmem --hints --rdahead=4";;
    "fswap")            LS=solid;       OPTS="$OPTS --fastswap";;
    "fswap+1")          LS=solid;       OPTS="$OPTS --fastswap --rdahead=1";;
    "fswap+3")          LS=dashed;      OPTS="$OPTS --fastswap --rdahead=3";;
    "fswap+7")          LS=dashdot;     OPTS="$OPTS --fastswap --rdahead=7";;
    *)                  echo "Unknown rmem type"; exit;;
    esac
}

set_scheduler() {
    sc=$1
    case $sc in
    "")                 ;;
    "pthreads")         OPTS="$OPTS --sched=pthreads";;
    "shenango")         OPTS="$OPTS --sched=shenango";;
    *)                  echo "Unknown scheduler"; exit;;
    esac
}

set_evict_opts() {
    evict=$1
    case $evict in
    "noevict")          ;;
    "evict")            OPTS="$OPTS --evict";;
    "evict-sc")         OPTS="$OPTS --evict --evictpolicy=SC";;
    "evict-lru")        OPTS="$OPTS --evict --evictpolicy=LRU";;
    "evict2")           OPTS="$OPTS --batchevict=2";;
    "evict4")           OPTS="$OPTS --batchevict=4";;
    "evict8")           OPTS="$OPTS --batchevict=8";;
    "evict16")          OPTS="$OPTS --batchevict=16";;
    "evict32")          OPTS="$OPTS --batchevict=32";;
    "evict64")          OPTS="$OPTS --batchevict=64";;
    *)                  echo "Unknown evict type"; exit;;
    esac
}

set_backend_opts() {
    bkend=$1
    case $bkend in
    "none")             ;;
    "local")            OPTS="$OPTS --bkend=local"; LS=solid;  CMI=1;;
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

measure_xput_vary_cpu()
{
    name="nohints"
    # sc="shenango"
    for bkend in "local"; do
        for rmem in "hints"; do
        # for rmem in "hints" "hints+1" "hints+2" "hints+4"; do
        # for rmem in "fswap"; do       # "fswap+1" "fswap+3" "fswap+7" ; do
            # for evict in "noevict" "evict" "evict2" "evict4" "evict8" "evict16" "evict32" "evict64"; do
            for evict in "evict"; do
                # for op in "read" "write"; do
                for op in "read" "write"; do
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
                    set_scheduler       "$sc"

                    # run and log result
                    datafile=$DATADIR/xput-${cfg}
                    if [ ! -f $datafile ] || [[ $FORCE ]]; then
                        bash run.sh --clean
                        # reloading fastswap everytime takes time
                        bash run.sh ${OPTS} -fl="""$CFLAGS""" --force --buildonly   #recompile
                        echo "cores,xput,reclaimcpu" > $datafile
                        for cores in `seq 1 1 12`; do 
                        # for cores in 1; do 
                            rm -f result
                            bash run.sh ${OPTS} -t=${cores} -fl="""$CFLAGS""" ${PRELOAD}
                            xput=$(cat result 2>/dev/null)
                            reclaimcpu=
                            if [ -f run_start ] && [ -f run_end ]; then
                                if [ "$rmem" == "fswap" ]; then
                                    cpuvals=$(bash ${ROOT_SCRIPTS_DIR}/parse_sar.sh -sf="cpu_reclaim.sar" -sc="%system" -t1=`cat run_start` -t2=`cat run_end` | tail -n+2)
                                    reclaimcpu=$(mean "$cpuvals")
                                elif [[ "$rmem" == "hints"* ]]; then
                                    python3 ../../scripts/parse_eden_rmem.py -i rmem-stats.out -st `cat run_start` -et `cat run_end` -o ${TMP_FILE_PFX}stats
                                    reclaimcpu=$(csv_column_mean "${TMP_FILE_PFX}stats" "cpu_per_h")
                                fi
                            fi
                            echo "$cores,$xput,$reclaimcpu" >> $datafile        # record xput

                            # clean and wait a bit
                            bash run.sh --clean
                            sleep 10
                        done
                    fi
                    cat $datafile
                    plots="$plots -d $datafile -l ${rmem}-${bkend} -ls $LS -cmi $CMI"
                    # plots="$plots -d $datafile -l ${evict}-${op} -ls $LS -cmi $CMI"
                done
            done
        done
    done

    if [[ $PLOT ]]; then
        mkdir -p ${PLOTDIR}
        plotname=${PLOTDIR}/fault_xput_cpu_${name}.${PLOTEXT}
        python ${PLOTSRC} ${plots}                  \
            -xc cores -xl "App CPU"                 \
            -yc xput -yl "MOPS" --ymul 1e-6         \
            --ymin 0 --ymax 3                       \
            --size 6 4 -fs 11 -of ${PLOTEXT} -o $plotname
        display $plotname &
    fi
}

measure_xput_vary_batch()
{
    name="local_hints_evict_read"
    for bkend in "local"; do
        for rmem in "hints"; do     # "hints+1" "hints+2" "hints+4"; do
            for evict in "evict"; do
                for op in "read" "write"; do
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
                    cores=8
                    datafile=$DATADIR/xput-${cores}cores-${cfg}
                    if [ ! -f $datafile ] || [[ $FORCE ]]; then
                        bash run.sh --clean
                        bash run.sh ${OPTS} -fl="""$CFLAGS""" --batchevict=1 --force --buildonly   #recompile
                        echo "cores,batchsize,xput" > $datafile
                        for batchsz in `seq 1 4 50`; do 
                            rm -f result
                            bash run.sh ${OPTS} -t=${cores} ${PRELOAD}      \
                                --batchevict=$batchsz -fl="""$CFLAGS"""
                            xput=$(cat result 2>/dev/null)
                            echo "$cores,$batchsz,$xput" >> $datafile   # record xput

                            # clean and wait a bit
                            bash run.sh --clean
                            sleep 10
                        done
                    fi
                    cat $datafile
                    # plots="$plots -d $datafile -l ${rmem}-${bkend} -ls $LS -cmi $CMI"
                    plots="$plots -d $datafile -l ${cores}cores-${op} -ls $LS -cmi $CMI"
                done
            done
        done
    done

    if [[ $PLOT ]]; then
        mkdir -p ${PLOTDIR}
        plotname=${PLOTDIR}/fault_xput_batch_${name}.${PLOTEXT}
        python ${PLOTSRC} ${plots}                  \
            -xc batchsize -xl "Batch Size"          \
            -yc xput -yl "MOPS" --ymul 1e-6         \
            --ymin 0 --ymax 3                       \
            --size 6 4 -fs 11 -of ${PLOTEXT} -o $plotname
        display $plotname &
    fi
}

measure_latency()
{
    for bkend in "local" "rdma"; do
        for rmem in "hints" "hints+1" "hints+2" "hints+4"; do
            for evict in "noevict" "evict" "evict2" "evict4" "evict8"; do
                for op in "read" "write"; do
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

test_every_config()
{
    configs="""
    normem  local   read    noevict
    nohints local   read    noevict
    nohints local   read    evict
    nohints local   write   evict
    hints   local   read    noevict
    hints   local   read    evict
    hints   local   write   evict
    hints+4 local   write   evict
    hints   local   read    evict4
    hints   local   write   evict4
    """
    rdma_configs="""
    nohints rdma    read    noevict
    hints   rdma    read    noevict
    hints   rdma    read    evict
    hints   rdma    write   evict
    hints+4 rdma    write   evict
    """

    result=test_result
    rm -f $result
    # echo "$configs" "$rdma_configs" | while read line;
    echo "$configs" | while read line;
    do
        if [ $(echo $line | awk '{  print NF }') -ne 4 ]; then
            continue
        fi
        echo "$line"
        rmem=$(echo $line | awk '{  print $1 }')
        bkend=$(echo $line | awk '{  print $2 }')
        op=$(echo $line | awk '{  print $3 }')
        evict=$(echo $line | awk '{  print $4 }')
        echo "testing $rmem $bkend $op $evict"

        # reset
        cfg=${rmem}-${evict}-${bkend}-${op}
        CFLAGS=${CFLAGS_BEFORE}
        OPTS=${OPTS_BEFORE}

        # set opts
        set_hints_opts      "$rmem"
        set_evict_opts      "$evict"
        set_backend_opts    "$bkend"
        set_fault_op_opts   "$op"

        # # run and log result
        bash run.sh --clean
        rm -f result
        bash run.sh ${OPTS} -t=12 -fl="""$CFLAGS""" --force
        xput=$(cat result 2>/dev/null)
        echo "$cfg passed xput for 1 core: $xput" >> $result
    done
    cat $result
}


if [[ $TEST ]]; then
    test_every_config
elif [[ $LATENCIES ]]; then
    measure_latency
else
    measure_xput_vary_cpu
    # measure_xput_vary_batch
fi

# cleanup
rm -f ${TEMP_PFX}*
