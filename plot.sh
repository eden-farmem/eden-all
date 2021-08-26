#!/bin/bash
# set -e 

PLOTEXT=png
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
# SUFFIX_SIMPLE="08-23-0[0-6]"
# SUFFIX_SIMPLE="08-23-10"
# SUFFIX_SIMPLE="08-23-11-[2-5]"
SUFFIX_SIMPLE="08-25-[01]"
# SUFFIX_COMPLX="08-22-\(10.*\|11.[0-1].*\)"
# SUFFIX_COMPLX="08-22-\(1[459].*\|20.*\)"
# # SUFFIX_COMPLX="08-24-\(0[89].*\|1[04].*\)"
SUFFIX_COMPLX="08-24-\(0[89].*\|[12].*\)"
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
    if [ $konamem == "null" ]; then    klabel="No_Kona";    konamem=0;
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
        python summary.py -n $name --lat --kona
    fi

    # Separate runs by a specific label type
    label=${mpps}_Mops
    label_str=OfferedLoad
    if [ "$label" != "$curlabel" ]; then 
        if [[ $curlabel ]]; then
            # echo -e "$header$stats" > temp_xput_$curlabel
            tmpfile=temp_xput_$curlabel
            echo -e "$stats" > $tmpfile
            sort -k3 -n -t, $tmpfile -o $tmpfile    #sort by konamem
            sed -i "1s/^/$header/" $tmpfile
            plots="$plots -l ${curlabel} -dyc temp_xput_$curlabel achieved"
            # plots="$plots -l ${curlabel} -dyc temp_xput_$curlabel tfaults"
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
    header=nconns,mpps,konamem,`cat $statfile | awk 'NR==1'`
    curstats=`cat $statfile | awk 'NR==2'`
    if ! [[ $curstats ]]; then    curstats=$prevstats;  fi      #HACK!
    stats="$stats\n$nconns,$mpps,$konamem,$curstats"
    prevstats=$curstats
    latfiles="$latfiles -d $statsdir/latencies_0 -l $klabel"
    konafiles="$konafiles -d $statsdir/konastats_0 -l $klabel"
    sed -i '8,$d' $statsdir/konastats_0     #HACK: make all files have same no of datapoints
done

# Xput plot over kona mem size by offered load
tmpfile=temp_xput_$curlabel
echo -e "$stats" > $tmpfile
sort -k3 -n -t, $tmpfile -o $tmpfile
sed -i "1s/^/$header/" $tmpfile
plots="$plots -l ${curlabel} -dyc temp_xput_$curlabel achieved"
# plots="$plots -l ${curlabel} -dyc temp_xput_$curlabel tfaults"
plotname=${PLOTDIR}/memcached_xput_${SUFFIX}.$PLOTEXT
python3 tools/plot.py ${plots}                      \
    -xc konamem -xl "Kona Mem (MB)" --xmul 1e-6     \
    -yl "Million ops/sec" --ymul 1e-6               \
    -fs 14 -of $PLOTEXT -o $plotname --ltitle $label_str
display $plotname &
rm temp_xput*
# #-yl "Million Ops/sec" --ymul 1e-6               \


# # Xput plot over kona mem size
# tmpfile=temp_xput_$curlabel
# echo -e "$stats" > $tmpfile
# sort -k3 -n -t, $tmpfile -o $tmpfile
# sed -i "1s/^/$header/" $tmpfile
# plots="$plots -d $tmpfile"
# cat $tmpfile
# plotname=${PLOTDIR}/memcached_xput_${SUFFIX}.$PLOTEXT
# python3 tools/plot.py ${plots}  \
#     -yc achieved -l "Throughput" -ls solid          \
#     -yc tfaults  -l "Pg Faults (All)" -ls dashed    \
#     -yc tfaults  -l "Pg Faults (Read)" -ls dashed   \
#     -xc konamem -xl "Kona Mem (MB)" --xmul 1e-6     \
#     -yl "Million Ops/sec" --ymul 1e-6               \
#     --twin 2 -tyl "Kilo Faults/sec" --tymul 1e-3 \
#     -fs 14 -of $PLOTEXT -o $plotname
# gv $plotname &
# rm $tmpfile

# # Xput plot over mpps
# echo -e "$header$stats" > temp_xput_$curlabel
# plots="$plots -dyc temp_xput_$curlabel achieved -l ${curlabel} ";   numplots=$((numplots+1));
# plots="$plots -yl Achieved --ymul 1e-6 "
# plotname=${PLOTDIR}/memcached_xput_${SUFFIX}.$PLOTEXT
# if [[ $SHOWCPU ]]; then
#     cpuplots="$cpuplots -l ${curlabel} -dyc temp_xput_$curlabel totalcpu";   numplots=$((numplots+1));
#     factor=`echo $HOST_CORES_PER_NODE | awk '{ print $1*1.0/100 }'`
#     # cpuplots="$cpuplots --twin $((numplots/2+1)) -tyl CpuCores --tymul $factor"
#     cpuplots="$cpuplots -yl CpuCores --ymul $factor"
#     plots="$cpuplots"
#     plotname=${PLOTDIR}/memcached_xput_cpu_${SUFFIX}.$PLOTEXT
# fi
# python3 tools/plot.py ${plots}       \
#     -xc konamem  -xl "Local Memory (MB)" --xmul 1e-6 \
#     -fs 14 -of $PLOTEXT -o $plotname --ltitle ${label_str}
# gv $plotname &
# rm temp_xput*

# # Latencies plot
# plotname=${PLOTDIR}/kona_latencies_${SUFFIX}.$PLOTEXT
# python3 tools/plot.py -z cdf  -yc "Latencies"  ${latfiles}  \
#     -xl  "Latencies (micro-sec)"    --xlog                  \
#     -fs 11  -of $PLOTEXT  -o $plotname
# gv $plotname &  

# # Kona faults plot
# plotname=${PLOTDIR}/kona_faults_${SUFFIX}.$PLOTEXT
# python3 tools/plot.py ${konafiles}          \
#     -yc "tfaults" -yl "Fault Count"         \
#     -xc time -xl  "Time (secs)"             \
#     -fs 12  -of $PLOTEXT  -o $plotname
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

# # ZIPF
# for N in 10000 1000000 10000000; do 
#     plots=
#     for ALPHA in 0.1 0.5 1 10; do 
#         plots="$plots -d zipf_${N}_$ALPHA -l alpha=$ALPHA"
#     done
#     plotname=${PLOTDIR}/zipf_cdf_${N}.$PLOTEXT
#     python tools/plot.py $plots -z cdf  \
#         -yc count -yl PDF --ylog        \
#         -xl "N" --ltitle "Zipf N=$N"    \
#         -of $PLOTEXT -o $plotname
#     display $plotname &
# done


