#!/bin/bash
# set -e

# Miscellaneous plots

PLOTEXT=png
PLOTDIR=plots/
HOST_CORES_PER_NODE=28
HOST="sc2-hs2-b1630"
CLIENT="sc2-hs2-b1607"
SCRIPT_DIR=`dirname "$0"`

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


# Madvise batching micro-benchmark
cat data/run-11-01-12-55/memcached.out  | egrep -o "Madvise for [0-9]+ pages took ([0-9]+) cycles" | awk ' NR == 1 { sum = 0; count = 0; } { sum += $6; count++; } END { print sum / count; } ' 
cat data/run-11-01-12-58/memcached.out  | egrep -o "Madvise for [0-9]+ pages took ([0-9]+) cycles" | awk ' NR == 1 { sum = 0; count = 0; } { sum += $6; count++; } END { print sum / (5*count); } ' 
cat data/run-11-01-13-01/memcached.out  | egrep -o "Madvise for [0-9]+ pages took ([0-9]+) cycles" | awk ' NR == 1 { sum = 0; count = 0; } { sum += $6; count++; } END { print sum / (10*count); } ' 
cat data/run-11-01-13-04/memcached.out  | egrep -o "Madvise for [0-9]+ pages took ([0-9]+) cycles" | awk ' NR == 1 { sum = 0; count = 0; } { sum += $6; count++; } END { print sum / (20*count); } '

plotname=${PLOTDIR}/eviction_batching2.${PLOTEXT}
python3 ${SCRIPT_DIR}/plot.py -d temp_madvise       \
    -xc batch -xl "Batch Size"                      \
    -yc latency                                     \
    -yl "Amortized (Cycles)" --ymul 1e-3            \
    --size 6 3 -fs 12 -of $PLOTEXT -o $plotname 
display $plotname & 

plotname=${PLOTDIR}/eviction_batching.${PLOTEXT}
python3 ${SCRIPT_DIR}/plot.py -z cdf -yc Latency        \
    -xl "Latency (Kilo Cycles)" --xmul 1e-3             \
    -d temp_madvise1    -l "1"                          \
    -d temp_madvise5    -l "5"                          \
    -d temp_madvise10   -l "10"                         \
    -d temp_madvise20   -l "20"                         \
    --size 6 3 -fs 12 -of $PLOTEXT -o $plotname -lt "Batch Size"
display $plotname & 


############# ARCHIVED ##############################

# # Eviction latency breakdown
# yes_madv=run-10-23-11-43
# no_madv=run-10-23-11-26

# python ${SCRIPT_DIR}/summary.py -n=${yes_madv} --kona
# python ${SCRIPT_DIR}/summary.py -n=${no_madv} --kona
# yes_data=data/${yes_madv}/stats/konastats_extended_aggregated_0
# no_data=data/${no_madv}/stats/konastats_extended_aggregated_0

# tmpfile=temp
# yes_madv=`jq ".PERF_EVICT_MADVISE" ${yes_data}`
# yes_wp=`jq ".PERF_EVICT_WP" ${yes_data}`
# yes_write=`jq ".PERF_EVICT_WRITE" ${yes_data}`
# yes_evict=`jq ".PERF_EVICT_TOTAL" ${yes_data}`
# yes_left=`echo $yes_evict,$yes_write,$yes_wp,$yes_madv | awk -F, '{ printf "%.1f",$1-$2-$3-$4 }'`
# no_madv=`jq ".PERF_EVICT_MADVISE" ${no_data}`
# no_wp=`jq ".PERF_EVICT_WP" ${no_data}`
# no_write=`jq ".PERF_EVICT_WRITE" ${no_data}`
# no_evict=`jq ".PERF_EVICT_TOTAL" ${no_data}`
# no_left=`echo $no_evict,$no_write,$no_wp,$no_madv | awk -F, '{ printf "%.1f",$1-$2-$3-$4 }'`
# echo "METRIC,WITH_MADV,NO_MADV" > ${tmpfile}
# echo "Total,${yes_evict},${no_evict}" >> ${tmpfile}
# echo "Rem Write,${yes_write},${no_write}" >> ${tmpfile}
# echo "Write Protect,${yes_wp},${no_wp}" >> ${tmpfile}
# echo "Madvise,${yes_madv},${no_madv}" >> ${tmpfile}
# echo "Other,${yes_left},${no_left}" >> ${tmpfile}
# # cat ${tmpfile}

# plotname=${PLOTDIR}/eviction_breakdown.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -d ${tmpfile} -z bar      \
#     -xc "METRIC" -xl "Eviction Breakdown"               \
#     -yc "WITH_MADV" -l "YES"      \
#     -yl "Latency (µs)" --ltitle "MAdvise Notify App"    \
#     --ymul 1e-3 --barwidth .3 --size 8 4  -of $PLOTEXT -o $plotname
# display $plotname &
# # rm ${tmpfile}

# # MEMCACHED MEM ACCESS
# expname="run-10-17-21-19"     # .001 Mpps
# expname="run-10-19-13-22"       # 2 Mpps
# expname="run-10-23-22-50"       # 2 mpps, with evict addrs
# python ${SCRIPT_DIR}/parse_addr_data.py -n ${expname}

# DATADIR=data/$expname/addrs/
# PLOTDIR=data/$expname/plots
# mkdir -p $PLOTDIR

# datafile=${DATADIR}/rfaults
# plotname=${PLOTDIR}/rfaults_gap.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -z scatter -d ${datafile}        \
#     -yc gap -yl "Read Gap" -xc "time"               \
#     --size 6 3 -of $PLOTEXT -o $plotname --xmin 40 --xmax 90
# display $plotname &

# datafile=${DATADIR}/wfaults
# plotname=${PLOTDIR}/wfaults_gap.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -z scatter -d ${datafile}        \
#     -yc gap -yl "Write Gap" -xc "time"               \
#     --size 6 3 -of $PLOTEXT -o $plotname --xmin 40 --xmax 90
# display $plotname &

# datafile=${DATADIR}/evictions
# plotname=${PLOTDIR}/evictions.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -z scatter -d ${datafile}         \
#     -yc addr -yl "Page Address" -xc time -xl "Time (secs)"      \
#     --size 8 4 -of $PLOTEXT -o $plotname --xmin 40 --xmax 90
# display $plotname &

# datafile=${DATADIR}/evictions
# plotname=${PLOTDIR}/evictions_gap.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -d ${datafile}        \
#     -yc gap -yl "Eviction Gap" -xc time -xl "Time (secs)"    \
#     --size 8 4 -of $PLOTEXT -o $plotname --xmin 40 --xmax 90
# display $plotname &

# datafile=${DATADIR}/counts
# plotname=${PLOTDIR}/counts.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -d ${datafile}         \
#     -yc rfaults -yc wfaults -yc evictions -xc "time" \
#     --size 8 4 -of $PLOTEXT -o $plotname --xmin 30 --xmax 90
# display $plotname &
# ==============================

# for f in `ls run*/stats/stat.csv`; do
# for f in `ls run.20210805082856-shenango-memcached-tcp/stats/stat.csv`; do
#     dir1=`dirname $f`;
#     dir=`dirname $dir1`;
#     mpps=`jq ".clients[] | .[0].start_mpps" $dir/config.json | paste -sd+ | bc`
#     echo $dir, $mpps
#     cat $f

#     plotname=$dir/plot_p99.$PLOTEXT
#     python3 ${SCRIPT_DIR}/plot.py -d $f \
#         -xc achieved -xl "Xput (Mpps)" --xmul 1e-6              \
#         -yc p99 -yl "Latency (micro-sec)" --ymin 0 --ymax 500   \
#         -of $PLOTEXT -o $plotname -s
#     gv $plotname &

#     shortid=`echo $dir | cut -b12-18`
#     plots="$plots -dyc $f p99 -l $shortid,$mpps "
# done

# echo $plots
# plotname=plots_p99.$PLOTEXT
# python3 ${SCRIPT_DIR}/plot.py $plots \
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
#     python ${SCRIPT_DIR}/plot.py $plots -z cdf  \
#         -yc count -yl PDF --ylog        \
#         -xl "N" --ltitle "Zipf N=$N"    \
#         -of $PLOTEXT -o $plotname
#     display $plotname &
# done


