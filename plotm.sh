#!/bin/bash
set -e 
#
# Plot all stats for multiple runs 
# (Requires Imagemagick)
#

PLOTEXT=png
DATADIR=data
PLOTDIR=plots/
HOST_CORES_PER_NODE=28
HOST="sc2-hs2-b1630"
CLIENT="sc2-hs2-b1607"
SAMPLE=0
SOME_BIG_NUMBER=100000000000

usage="\n
-s, --suffix \t\t a plain suffix defining the set of runs to consider\n
-cs, --csuffix \t\t same as suffix but a more complex one (with regexp pattern)\n
-d, --display \t\t display individal plots\n
-f, --force \t\t force re-summarize results\n"

for i in "$@"
do
case $i in
    -s=*|--suffix=*)
    SUFFIX="${i#*=}"
    ;;

    -cs=*|--csuffix=*)
    CSUFFIX="${i#*=}"
    ;;

    -d|--display)
    DISPLAY_EACH=1
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

# Some previous runs
# CSUFFIX="08-25-\(09*\|10.*\|11.[12].*\)"              # Runs with 4 server cores
# SUFFIX="08-27-1[89]"                                  # Runs with 4 server cores (latest)
# SUFFIX="08-28-10"                                     # Runs with 12 server cores


if [[ $SUFFIX ]]; then 
    LS_CMD=`ls -d1 data/run-${SUFFIX}*/`
    SUFFIX=$SUFFIX
elif [[ $CSUFFIX ]]; then
    LS_CMD=`ls -d1 data/*/ | grep -e "$CSUFFIX"`
    SUFFIX=$CSUFFIX
fi

numplots=0
for exp in $LS_CMD; do
    echo "Parsing $exp"
    name=`basename $exp`
    cfg="$exp/config.json"
    sthreads=`jq '.apps."'$HOST'" | .[] | select(.name=="memcached") | .threads' $cfg`
    konamem=`jq '.apps."'$HOST'" | .[] | select(.name=="memcached") | .kona.mlimit' $cfg`
    if [ $konamem == "null" ]; then    klabel="No_Kona";    konamem_mb=$SOME_BIG_NUMBER;
    else    konamem_mb=`echo $konamem | awk '{ print $1/1000000 }'`;     fi
    label=$klabel
    prot=`jq -r '.clients."'$CLIENT'" | .[] | select(.app=="synthetic") | .transport' $cfg`
    nconns=`jq '.clients."'$CLIENT'" | .[] | select(.app=="synthetic") | .client_threads' $cfg`
    mpps=`jq '.clients."'$CLIENT'" | .[] | select(.app=="synthetic") | .mpps' $cfg`
    desc=`jq '.desc' $cfg`

    # summarize results
    statsdir=$exp/stats
    statfile=$statsdir/stat.csv
    if [[ $FORCE ]] || [ ! -d $statsdir ]; then
        python summary.py -n $name --lat --kona --app --iok
    fi
    
    # aggregate across runs
    header=nconns,mpps,konamem,scores,`cat $statfile | awk 'NR==1'`
    curstats=`cat $statfile | awk 'NR==2'`
    # if ! [[ $curstats ]]; then    curstats=$prevstats;  fi      #HACK!
    stats="$stats\n$nconns,$mpps,$konamem_mb,$sthreads,$curstats"
    prevstats=$curstats
done

# Data in one file
tmpfile=temp_xput_$curlabel
echo -e "$stats" > $tmpfile
# sort -k3 -n -t, $tmpfile -o $tmpfile
sort -k4 -n -t, $tmpfile -o $tmpfile
sed -i "1s/^/$header/" $tmpfile
sed -i "s/$SOME_BIG_NUMBER/NoKona/" $tmpfile
plots="$plots -d $tmpfile"
cat $tmpfile
datafile=$tmpfile

# Plot memcached
plotname=${PLOTDIR}/memcached_xput_${SUFFIX}.$PLOTEXT
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
    python3 tools/plot.py -d ${datafile}                \
        -yc achieved -l "Throughput" -ls solid          \
        -xc scores -xl "Server Cores" --xstr          \
        -yl "Million Ops/sec" --ymul 1e-6               \
        -fs 12 -of $PLOTEXT -o $plotname
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

# Plot kona 
plotname=${PLOTDIR}/konastats_${SUFFIX}.$PLOTEXT
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
    datafile_kona="temp_kona"
    sed '/NoKona/d' $datafile > $datafile_kona      #remove nokona run
    python3 tools/plot.py -d ${datafile_kona}               \
        -yc "n_faults" -l "Total Faults" -ls solid          \
        -yc "n_net_page_in" -l "Net Pages Read" -ls solid   \
        -yc "n_net_page_out" -l "Net Pages Write" -ls solid \
        -yc "malloc_size" -l "Mallocd Mem" -ls dashed       \
        -yc "mem_pressure" -l "Mem pressure" -ls dashed     \
        -xc scores -xl "Server Cores" --xstr              \
        -yl "Count (x1000)" --ymul 1e-3 --ymin 0            \
        --twin 4  -tyl "Size (MB)" --tymul 1e-6 --tymin 0   \
        -fs 12  -of $PLOTEXT  -o $plotname -t "Kona"    
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

# Plot iok stats
plotname=${PLOTDIR}/iokstats_${SUFFIX}.$PLOTEXT
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
python3 tools/plot.py -d ${datafile}                        \
    -yc "TX_PULLED" -l "From Runtime" -ls solid             \
    -yc "RX_PULLED" -l "To Runtime" -ls solid               \
    -yc "RX_UNICAST_FAIL" -l "To Runtime (Failed)" -ls solid      \
    -yc "IOK_SATURATION" -l "Core Saturation" -ls dashed    \
    -xc scores -xl "Server Cores" --xstr                  \
    -yl "Million pkts/sec" --ymul 1e-6 --ymin 0             \
    --twin 4  -tyl "Saturation %" --tymul 100 --tymin 0 --tymax 110   \
    -fs 12 -of $PLOTEXT  -o $plotname -t "Shenango I/O Core"
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

# Plot runtime stats
plotname=${PLOTDIR}/${name}_runtime.$PLOTEXT
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
    python3 tools/plot.py -d ${datafile}                        \
        -yc "rxpkt" -l "From I/O Core" -ls solid                \
        -yc "txpkt" -l "To I/O Core" -ls solid                  \
        -yc "drops" -l "Pkt drops" -ls solid                    \
        -yc "cpupct" -l "CPU Utilization" -ls dashed            \
        -xc scores -xl "Server Cores" --xstr                  \
        -yl "Million pkts/sec" --ymul 1e-6 --ymin 0             \
        --twin 4  -tyl "CPU Cores" --tymul 1e-2 --tymin 0       \
        -fs 12  -of $PLOTEXT  -o $plotname -t "Shenango Resources"
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

plotname=${PLOTDIR}/${name}_scheduler.$PLOTEXT
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
    python3 tools/plot.py -d ${datafile}                        \
        -yc "stolenpct" -l "Stolen Work %" -ls solid            \
        -yc "migratedpct" -l "Core Migration %" -ls solid       \
        -yc "localschedpct" -l "Core Local Work %" -ls solid    \
        -yc "rescheds" -l "Reschedules" -ls dashed              \
        -yc "parks" -l "KThread Parks" -ls dashed               \
        -xc scores -xl "Server Cores" --xstr                  \
        -yl "Percent" --ymin 0 --ymax 110                       \
        --twin 4  -tyl "Million Times" --tymul 1e-6 --tymin 0   \
        -fs 12  -of $PLOTEXT  -o $plotname -t "Shenango Scheduler" 
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

# Write config params 
echo "text 3,6 \"" > temp_cfg 
echo "        INFO" >> temp_cfg 
echo "        Server Cores: $sthreads" >> temp_cfg 
echo "        Offered Load: $mpps MOps" >> temp_cfg 
echo "\"" >> temp_cfg 
convert -size 360x120 xc:white -font "DejaVu-Sans" -pointsize 20 -fill black -draw @temp_cfg temp_image.png
files="$files temp_image.png"

# # Combine
# echo $files
plotname=${PLOTDIR}/all_${SUFFIX}.$PLOTEXT
montage -tile 2x0 -geometry +5+5 -border 5 $files ${plotname}
display ${plotname} &
rm $datafile
rm temp_*
