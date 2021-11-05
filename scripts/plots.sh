#!/bin/bash
set -e 
#
# Plot all stats for a single run
#

PLOTEXT=png
DATADIR=data
PLOTDIR=plots/
HOST_CORES_PER_NODE=28
HOST="sc2-hs2-b1630"
CLIENT="sc2-hs2-b1607"
SAMPLE=0

usage="\n
-n, --name \t\t experiment to consider\n
-f, --force \t\t force re-summarize results\n"

for i in "$@"
do
case $i in
    -n=*|--name=*)
    NAME="${i#*=}"
    ;;

    -f|--force)
    FORCE=1
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# Exp run, pick latest by default
latest_dir_path=$(ls -td -- $DATADIR/*/ | head -n 1)
name=${NAME:-$(basename $latest_dir_path)}
echo "Working on experiment:" $name
exp=$DATADIR/$name
SCRIPT_DIR=`dirname "$0"`

# summarize results
statsdir=$exp/stats
statfile=$statsdir/stat.csv
if [[ $FORCE ]] || [ ! -d $statsdir ]; then
    python ${SCRIPT_DIR}/summary.py -n $name --lat --kona --iok --app -so 60
fi
ls $statsdir

# Plot memcached
datafile=$statsdir/stat.csv
# get offered and achieved xput 

# Plot kona 
datafile=$statsdir/konastats_$SAMPLE
if [ -f $datafile ]; then 
    plotname=${PLOTDIR}/${name}_konastats.$PLOTEXT
    # python3 ${SCRIPT_DIR}/plot.py -d ${datafile}            \
    #     -yc "n_faults" -l "Total Faults" -ls solid          \
    #     -yc "n_net_page_in" -l "Net Pages Read" -ls solid   \
    #     -yc "n_net_page_out" -l "Net Pages Write" -ls solid \
    #     -yc "n_madvise_try" -l "Num Madvise" -ls solid      \
    #     -yc "malloc_size" -l "Mallocd Mem" -ls dashed       \
    #     -yc "mem_pressure" -l "Mem pressure" -ls dashed     \
    #     -xc "time" -xl  "Time (secs)" -yl "Count (x1000)"   \
    #     --twin 5  -tyl "Size (GB)" --tymul 1e-9 --ymul 1e-3 \
    #     --ymin 0 --tymin 0 -t "Kona"   \
    #     -fs 12  -of $PLOTEXT  -o $plotname
    python3 ${SCRIPT_DIR}/plot.py -d ${datafile}            \
        -yc "n_faults" -l "Total Faults" -ls solid          \
        -yc "n_faults_r" -l "Read Faults" -ls solid         \
        -yc "n_faults_w" -l "Write Faults" -ls solid        \
        -yc "n_faults_wp" -l "Remove WP" -ls solid          \
        -yc "n_net_page_in" -l "Net In" -ls solid           \
        -yc "n_net_page_out" -l "Net Out" -ls solid         \
        -yc "n_madvise"     -l "Madvise Calls"  -ls solid   \
        -yc "n_madvise_fail" -l "Madvise Fails" -ls solid   \
        -xc "time" -xl  "Time (secs)" -yl "Count (x 1000)"  \
        --ymin 0 --ymax 70 -lt "Kona Faults"  --ymul 1e-3   \
        --size 6 3 -fs 12  -of $PLOTEXT  -o $plotname
    files="$files $plotname"
    # display $plotname &  
fi

datafile=$statsdir/konastats_extended_$SAMPLE
if [ -f $datafile ]; then 
    plotname=${PLOTDIR}/${name}_konastats_extended.$PLOTEXT
    python3 ${SCRIPT_DIR}/plot.py -d ${datafile}                    \
        -yc "PERF_EVICT_TOTAL" -l "Total Eviction" -ls solid        \
        -yc "PERF_EVICT_WP" -l "Eviction WP" -ls solid              \
        -yc "PERF_RDMA_WRITE" -l "Issue Write" -ls solid            \
        -yc "PERF_POLLER_READ" -l "Handle Read" -ls dashed          \
        -yc "PERF_POLLER_UFFD_COPY" -l "UFFD Copy" -ls dashed       \
        -yc "PERF_HANDLER_RW" -l "Handle Fault" -ls dashed          \
        -yc "PERF_PAGE_READ" -l "RDMA Read" -ls dashed              \
        -yc "PERF_EVICT_WRITE" -l "Issue Write 2" -ls dashed        \
        -yc "PERF_HANDLER_FAULT" -l "Handle Fault 2" -ls dashed     \
        -yc "PERF_EVICT_MADVISE" -l "Evict Madvise" -ls dashed      \
        -xc "time" -xl "Time (secs)"                       \
        -yl "Micro-secs" --ymin 0 --ymax 70 --ymul 1e-3               \
        --size 6 3 -fs 10 -of $PLOTEXT  -o $plotname -lt "Kona Latencies"
    files="$files $plotname"
    # display $plotname &  
fi

# Plot iok stats
datafile=$statsdir/iokstats_$SAMPLE
if [ -f $datafile ]; then 
    plotname=${PLOTDIR}/${name}_iokstats.$PLOTEXT
    python3 ${SCRIPT_DIR}/plot.py -d ${datafile}                \
        -yc "TX_PULLED" -l "Acheived" -ls solid             \
        -yc "RX_PULLED" -l "Offered" -ls solid                 \
        -xc "time" -xl  "Time (secs)" -yl "Million pkts/sec"    \
        --ymin 0 --ymax 2.1 --ymul 1e-6 -lt "Shenango I/O Core"   \
        --size 6 3 -fs 12 -of $PLOTEXT  -o $plotname
    files="$files $plotname"
    # display $plotname & 
        # --twin 3  -tyl "Saturation %" --tymul 100  --tymax 110 --tymin 0     \
        # -yc "IOK_SATURATION" -l "Core Saturation" -ls dashed    \
fi

# Plot runtime stats
datafile=$statsdir/rstat_memcached_$SAMPLE
if [ -f $datafile ]; then 
    plotname=${PLOTDIR}/${name}_runtime.$PLOTEXT
    python3 ${SCRIPT_DIR}/plot.py -d ${datafile}                \
        -yc "rxpkt" -l "From I/O Core" -ls solid                \
        -yc "txpkt" -l "To I/O Core" -ls solid                  \
        -yc "drops" -l "Pkt drops" -ls solid                    \
        -yc "cpupct" -l "CPU Utilization" -ls dashed            \
        -xc "time" -xl  "Time (secs)" -yl "Million pkts/sec"    \
        --twin 4  -tyl "CPU Cores" --tymul 1e-2 --ymul 1e-6     \
        --tymin 0 --ymin 0 -lt "Shenango Runtime"               \
        --size 6 3 -fs 12  -of $PLOTEXT  -o $plotname
    files="$files $plotname"
    # display $plotname & 

    # plotname=${PLOTDIR}/${name}_scheduler.$PLOTEXT
    # python3 ${SCRIPT_DIR}/plot.py -d ${datafile}                \
    #     -yc "stolenpct" -l "Stolen Work %" -ls solid            \
    #     -yc "migratedpct" -l "Core Migration %" -ls solid       \
    #     -yc "localschedpct" -l "Core Local Work %" -ls solid    \
    #     -yc "rescheds" -l "Reschedules" -ls dashed              \
    #     -yc "parks" -l "KThread Parks" -ls dashed               \
    #     -xc "time" -xl  "Time (secs)" -yl "Percent"             \
    #     --twin 4  -tyl "Million Times" --tymul 1e-6             \
    #     --tymin 0 --ymin 0 --ymax 110 -t "Shenango Scheduler"   \
    #     --size 6 3 -fs 12  -of $PLOTEXT  -o $plotname
    # files="$files $plotname"
    # display $plotname & 
fi

# Combine
echo $files
plotname=${PLOTDIR}/${name}_all_1.$PLOTEXT
montage -tile 2x0 -geometry +5+5 -border 5 $files ${plotname}
cp ${plotname} $exp/
display ${plotname} &
