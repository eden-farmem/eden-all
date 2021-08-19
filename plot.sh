#!/bin/bash
# set -e 

PLOTEXT=pdf
PLOTDIR=plots/
HOST="sc2-hs2-b1630"

usage="\n
-f, --force \t\t force re-summarize results\n
-h, --help \t\t this usage information message\n"

for i in "$@"
do
case $i in
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


for exp in `ls -d1 data/run-08-19-00*`; do
    # echo $f
    name=`basename $exp`
    cfg="$exp/config.json"
    konamem=`jq '.apps."'$HOST'" | .[] | select(.name=="memcached") | .kona.mlimit' $cfg`
    if [ $konamem == "null" ]; then    klabel="No_Kona";
    else    klabel=`echo $konamem | awk '{ printf "%-4d_MB", $1/1000000 }'`;     fi
    # echo $klabel

    # summarize results
    statsdir=$exp/stats
    if [[ $FORCE ]] || [ ! -d $statsdir ]; then
        python summary.py -n $name --lat 
        break
    fi

    # aggregate across runs
    statfile=$statsdir/stat.csv
    header=`cat $statfile | awk 'NR==1'`,konamem
    curstats=`cat $statfile | awk 'NR==2'`,$konamem      #remove header
    stats="$stats\n$curstats"
    latfiles="$latfiles -d $statsdir/latencies_0 -l $klabel"
done

# Xput plot
echo -e "$header$stats" > temp_xput
plotname=${PLOTDIR}/kona_xput.$PLOTEXT
python3 tools/plot.py -d temp_xput      \
    -xc konamem  -xl "Local Memory (MB)" --xmul 1e-6    \
    -yc achieved -yl "Mpps" -l "Xput"   --ymul 1e-6     \
    --vline 1920                                        \
    -fs 14 -of $PLOTEXT -o $plotname
gv $plotname &
rm temp_xput
# --twin -yc totalcpu -tyl "CPU %"  -l "CPU Usage"          \

# Latencies plot
plotname=${PLOTDIR}/kona_latencies.$PLOTEXT
python3 tools/plot.py -z cdf  -yc "Latencies"  ${latfiles}  \
    -xl  "Latencies (micro-sec)"    --xlog                  \
    -fs 11  -of $PLOTEXT  -o $plotname
gv $plotname &  
















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


