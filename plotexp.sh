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

# summarize results
statsdir=$exp/stats
statfile=$statsdir/stat.csv
if [[ $FORCE ]] || [ ! -d $statsdir ]; then
    python summary.py -n $name --lat --kona --iok --app
fi
ls $statsdir

# Plot memcached
datafile=$statsdir/stat.csv
# get offered and achieved xput 

# Plot kona 
datafile=$statsdir/konastats_$SAMPLE
plotname=${PLOTDIR}/${name}_konastats.$PLOTEXT
python3 tools/plot.py -d ${datafile}                    \
    -yc "n_faults" -l "Total Faults" -ls solid          \
    -yc "n_net_page_in" -l "Net Pages Read" -ls solid   \
    -yc "n_net_page_out" -l "Net Pages Write" -ls solid \
    -yc "malloc_size" -l "Mallocd Mem" -ls dashed       \
    -yc "mem_pressure" -l "Mem pressure" -ls dashed     \
    -xc "time" -xl  "Time (secs)" -yl "Count (x1000)"   \
    --twin 4  -tyl "Size (GB)" --tymul 1e-9 --ymul 1e-3 \
    --ymin 0 --tymin 0 -t "Kona"   \
    -fs 12  -of $PLOTEXT  -o $plotname
files="$files $plotname"
# display $plotname &  

# Plot iok stats
datafile=$statsdir/iokstats_$SAMPLE
plotname=${PLOTDIR}/${name}_iokstats.$PLOTEXT
python3 tools/plot.py -d ${datafile}                        \
    -yc "TX_PULLED" -l "From Runtime" -ls solid             \
    -yc "RX_PULLED" -l "From NIC" -ls solid                 \
    -yc "IOK_SATURATION" -l "Core Saturation" -ls dashed    \
    -xc "time" -xl  "Time (secs)" -yl "Million pkts/sec"    \
    --twin 3  -tyl "Saturation %" --tymul 100 --ymul 1e-6   \
    --tymin 0 --ymin 0 --tymax 110 -t "Shenango I/O Core"   \
    -fs 12 -of $PLOTEXT  -o $plotname
files="$files $plotname"
# display $plotname & 

# Plot runtime stats
datafile=$statsdir/rstat_memcached_$SAMPLE
plotname=${PLOTDIR}/${name}_runtime.$PLOTEXT
python3 tools/plot.py -d ${datafile}                        \
    -yc "rxpkt" -l "From I/O Core" -ls solid                \
    -yc "txpkt" -l "To I/O Core" -ls solid                  \
    -yc "drops" -l "Pkt drops" -ls solid                    \
    -yc "cpupct" -l "CPU Utilization" -ls dashed            \
    -xc "time" -xl  "Time (secs)" -yl "Million pkts/sec"    \
    --twin 4  -tyl "CPU Cores" --tymul 1e-2 --ymul 1e-6     \
    --tymin 0 --ymin 0 -t "Shenango Resources"              \
    -fs 12  -of $PLOTEXT  -o $plotname
files="$files $plotname"
# display $plotname & 

plotname=${PLOTDIR}/${name}_scheduler.$PLOTEXT
python3 tools/plot.py -d ${datafile}                        \
    -yc "stolenpct" -l "Stolen Work %" -ls solid            \
    -yc "migratedpct" -l "Core Migration %" -ls solid       \
    -yc "localschedpct" -l "Core Local Work %" -ls solid    \
    -yc "parks" -l "KThread Parks" -ls solid                \
    -yc "rescheds" -l "Reschedules" -ls dashed              \
    -xc "time" -xl  "Time (secs)" -yl "Percent"             \
    --twin 5  -tyl "Million Times" --tymul 1e-6             \
    --tymin 0 --ymin 0 --ymax 110 -t "Shenango Scheduler"   \
    -fs 12  -of $PLOTEXT  -o $plotname
files="$files $plotname"
# display $plotname & 

# Combine
echo $files
montage -tile 2x0 -geometry +5+5 -border 5 $files ${exp}_all.png
display ${exp}_all.png &




