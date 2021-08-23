#!/bin/bash
# set -e 

PLOTEXT=pdf
PLOTDIR=plots/
HOST_CORES_PER_NODE=28
HOST="sc2-hs2-b1630"
CLIENT="sc2-hs2-b1607"

usage="\n
-f, --force \t\t force re-summarize results\n
-c, --cpu \t\t include cpu usage in xput plots\n
-h, --help \t\t this usage information message\n"

for i in "$@"
do
case $i in
    -f|--force)
    FORCE=1
    ;;
    
    -c|--cpu)
    SHOWCPU=1
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# SUFFIX_SIMPLE="08-22-1[012]"
# SUFFIX_SIMPLE="08-22-14"
SUFFIX_SIMPLE="08-23-0[0-6]"
# SUFFIX_COMPLX="08-22-\(10.*\|11.[0-1].*\)"
# SUFFIX_COMPLX="08-22-\(1[459].*\|20.*\)"
if [[ $SUFFIX_SIMPLE ]]; then 
    LS_CMD=`ls -d1 data/run-${SUFFIX_SIMPLE}*`
    SUFFIX=$SUFFIX_SIMPLE
elif [[ $SUFFIX_COMPLX ]]; then
    LS_CMD=`ls -d1 data/* | grep -e "$SUFFIX_COMPLX"`
    SUFFIX=$SUFFIX_COMPLX
fi

numplots=0
for exp in $LS_CMD; do
    # echo $f
    name=`basename $exp`
    cfg="$exp/config.json"
    sthreads=`jq '.apps."'$HOST'" | .[] | select(.name=="memcached") | .threads' $cfg`
    konamem=`jq '.apps."'$HOST'" | .[] | select(.name=="memcached") | .kona.mlimit' $cfg`
    if [ $konamem == "null" ]; then    klabel="No_Kona";
    else    klabel=`echo $konamem | awk '{ printf "%-4d_MB", $1/1000000 }'`;     fi
    label=$klabel
    prot=`jq -r '.clients."'$CLIENT'" | .[] | select(.app=="synthetic") | .transport' $cfg`
    nconns=`jq '.clients."'$CLIENT'" | .[] | select(.app=="synthetic") | .client_threads' $cfg`
    mpps=`jq '.clients."'$CLIENT'" | .[] | select(.app=="synthetic") | .mpps' $cfg`
    desc=`jq '.desc' $cfg`

    # summarize results
    statsdir=$exp/stats
    statfile=$statsdir/stat.csv
    if [[ $FORCE ]] || [ ! -d $statsdir ]; then
        python summary.py -n $name --lat 
    fi

    # Separate runs by a specific label type
    label=${prot}_${nconns}
    label_str=Transport
    if [ "$label" != "$curlabel" ]; then 
        if [[ $curlabel ]]; then
            echo -e "$header$stats" > temp_xput_$curlabel
            plots="$plots -l ${curlabel} -dyc temp_xput_$curlabel achieved"
            numplots=$((numplots+1))
            if [[ $SHOWCPU ]]; then
                cpuplots="$cpuplots -l ${curlabel} -dyc temp_xput_$curlabel totalcpu"
                numplots=$((numplots+1))
            fi
            stats=
        fi
        curlabel=$label
    fi
    
    # aggregate across runs
    header=`cat $statfile | awk 'NR==1'`,nconns,mpps,konamem
    curstats=`cat $statfile | awk 'NR==2'`
    if ! [[ $curstats ]]; then    curstats=$prevstats;  fi      #HACK!
    stats="$stats\n$curstats,$nconns,$mpps,$konamem"
    prevstats=$curstats
    latfiles="$latfiles -d $statsdir/latencies_0 -l $klabel"
done

# # Xput plot over kona mem size
# echo -e "$header$stats" > temp_xput_$curlabel
# plots="$plots -d temp_xput_$curlabel -l ${curlabel} "
# plotname=${PLOTDIR}/memcached_xput_${SUFFIX}.$PLOTEXT
# python3 tools/plot.py ${plots}  -yc achieved    \
#     -xc konamem -xl "Kona Mem (MB)" --xmul 1e-6 \
#     -yl "Achieved (Mpps)" --ymul 1e-6           \
#     -fs 14 -of $PLOTEXT -o $plotname
# gv $plotname &
# rm temp_xput_*

# Xput plot over mpps
echo -e "$header$stats" > temp_xput_$curlabel
plots="$plots -l ${curlabel} -dyc temp_xput_$curlabel achieved";   numplots=$((numplots+1));
plots="$plots -yl Achieved --ymul 1e-6"
plotname=${PLOTDIR}/memcached_xput_${SUFFIX}.$PLOTEXT
if [[ $SHOWCPU ]]; then
    cpuplots="$cpuplots -l ${curlabel} -dyc temp_xput_$curlabel totalcpu";   numplots=$((numplots+1));
    factor=`echo $HOST_CORES_PER_NODE | awk '{ print $1*1.0/100 }'`
    # cpuplots="$cpuplots --twin $((numplots/2+1)) -tyl CpuCores --tymul $factor"
    cpuplots="$cpuplots -yl CpuCores --ymul $factor"
    plots="$cpuplots"
    plotname=${PLOTDIR}/memcached_xput_cpu_${SUFFIX}.$PLOTEXT
fi
python3 tools/plot.py ${plots}       \
    -xc mpps  -xl "Offered Load (Mpps)"         \
    -fs 14 -of $PLOTEXT -o $plotname --ltitle ${label_str}
gv $plotname &
rm temp_xput*

# # Latencies plot
# plotname=${PLOTDIR}/kona_latencies_${SUFFIX}.$PLOTEXT
# python3 tools/plot.py -z cdf  -yc "Latencies"  ${latfiles}  \
#     -xl  "Latencies (micro-sec)"    --xlog                  \
#     -fs 11  -of $PLOTEXT  -o $plotname
# gv $plotname &  






############# ARCHIVED ##############################

# for f in `ls run*/stats/stat.csv`; do 
# for f in `ls run.20210805082856-shenango-memcached-tcp/stats/stat.csv`; do 
#     dir1=`dirname $f`; 
#     dir=`dirname $dir1`; 
#     mpps=`jq ".clients[] | .[0].start_mpps" $dir/config.json | paste -sd+ | bc`
#     echo $dir, $mpps
#     cat $f
    
#     plotname=$dir/plot_p99.$PLOTEXT
#     python3 tools/plot.py -d $f \
#         -xc achieved -xl "Xput (Mpps)" --xmul 1e-6              \
#         -yc p99 -yl "Latency (micro-sec)" --ymin 0 --ymax 500   \
#         -of $PLOTEXT -o $plotname -s
#     gv $plotname &

#     shortid=`echo $dir | cut -b12-18`
#     plots="$plots -dyc $f p99 -l $shortid,$mpps "
# done

# echo $plots
# plotname=plots_p99.$PLOTEXT
# python3 tools/plot.py $plots \
#     -xc achieved -xl "Xput (Mpps)" --xmul 1e-6      \
#     -yl "Latency (micro-sec)" --ymin 0 --ymax 500   \
#     -of $PLOTEXT -o $plotname -s
# gv $plotname &


