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
SOME_BIG_NUMBER=100000000000000


# Against Server Cores
PLOTSET=1
SUFFIX=09-01-1[67]
XCOL=scores
XLABEL="Application CPU Cores"
XCOLOFFSET=4
XSTR=

# # Against Kona Memory
# PLOTSET=2
# CSUFFIX="08-27-\(18-[2-5].*\|19.*\)"
# XCOL=konamem
# XLABEL="Local Memory Ratio"
# XMUL="--xmul 4.16e-4"           # 1920 MB, 0.8 evict thr
# XCOLOFFSET=3
# XSTR=

if [[ $SUFFIX ]]; then 
    LS_CMD=`ls -d1 data/run-${SUFFIX}*/`
    SUFFIX=$SUFFIX
elif [[ $CSUFFIX ]]; then
    LS_CMD=`ls -d1 data/*/ | grep -e "$CSUFFIX"`
    SUFFIX=$CSUFFIX
fi
# echo $LS_CMD

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
        python summary.py -n $name --kona --app --iok   #--lat
    fi
    
    # aggregate across runs
    header=nconns,mpps,konamem,scores,`cat $statfile | awk 'NR==1'`
    curstats=`cat $statfile | awk 'NR==2'`
    # if ! [[ $curstats ]]; then    curstats=$prevstats;  fi      #HACK!
    stats="$stats\n$nconns,$mpps,$konamem_mb,$sthreads,$curstats"
    prevstats=$curstats
done

# Collect and sort data
tmpfile=temp_xput_$curlabel
echo -e "$stats" > $tmpfile
sort -k${XCOLOFFSET} -n -t, $tmpfile -o $tmpfile
sed -i "1s/^/$header/" $tmpfile
sed -i "s/$SOME_BIG_NUMBER/NoKona/" $tmpfile
plots="$plots -d $tmpfile"
cat $tmpfile
datafile=$tmpfile

if [ "$PLOTSET" -eq 1 ]; then
    Plot memcached xput
    plotname=${PLOTDIR}/talk_scores_xput_${SUFFIX}.$PLOTEXT
    python3 tools/plot.py -d ${datafile}                \
        -yc achieved -l "Throughput" -ls solid          \
        -xc ${XCOL} -xl "$XLABEL" ${XSTR} ${XMUL}       \
        -yl "Million Ops/sec" --ymul 1e-6  --ymax .3    \
        -fs 15 -of $PLOTEXT -o $plotname
    display $plotname &  

    plotname=${PLOTDIR}/talk_scores_xput2_${SUFFIX}.$PLOTEXT
    python3 tools/plot.py -d ${datafile}                \
        -yc achieved -l "Throughput" -ls solid          \
        -yc "n_faults" -l "Page Faults" -ls dashed      \
        -xc ${XCOL} -xl "$XLABEL" ${XSTR} ${XMUL}       \
        -yl "Million Ops/sec" --ymul 1e-6  --ymax .3    \
        --twin 2 -tyl "Count x 1000" --tymul 1e-3 --tymin 0 --tymax 50  \
        -fs 15 -of $PLOTEXT -o $plotname
    display $plotname &  

    # Plot kona 
    plotname=${PLOTDIR}/talk_scores_kona1_${SUFFIX}.$PLOTEXT
    python3 tools/plot.py -d ${datafile}                    \
        -yc "PERF_HANDLER_FAULT_Q" -l "Eviction Queue Wait" \
        -xc ${XCOL} -xl "$XLABEL" ${XSTR} ${XMUL}           \
        -yl "µs" --ymin 0 --ymax 300 --ymul 454e-6          \
        -fs 15  -of $PLOTEXT  -o $plotname  
    display $plotname &  

    plotname=${PLOTDIR}/talk_scores_kona2_${SUFFIX}.$PLOTEXT
    python3 tools/plot.py -d ${datafile}                    \
        -yc "PERF_HANDLER_FAULT_Q" -l "Eviction Queue Wait" -ls solid   \
        -yc "PERF_PAGE_READ" -l "RDMA Read" -ls dashed                  \
        -yc "PERF_POLLER_UFFD_COPY" -l "Userfault Copy" -ls dashed      \
        -yc "PERF_EVICT_TOTAL" -l "Eviction Total" -ls dashed           \
        -yc "PERF_EVICT_MADVISE" -l "Madvise" -ls dashed                \
        -xc ${XCOL} -xl "$XLABEL" ${XSTR} ${XMUL}                       \
        -yl "µs" --ymin 0 --ymax 250 --ymul 454e-6                      \
        -fs 13  -of $PLOTEXT  -o $plotname  
    display $plotname &  

    # plotname=${PLOTDIR}/talk_scores_kona3_${SUFFIX}.$PLOTEXT
    # python3 tools/plot.py -d ${datafile}                    \
    #     -yc "PERF_HANDLER_FAULT_Q" -l "Eviction Queue Wait" -ls solid   \
    #     -yc "scores"   -l "Max Queue Size" -ls dashed                   \
    #     -xc ${XCOL} -xl "$XLABEL" ${XSTR} ${XMUL}                       \
    #     -yl "µs" --ymin 0 --ymax 250 --ymul 454e-6                      \
    #     --twin 2  -tyl "Count"                                          \
    #     -fs 13  -of $PLOTEXT  -o $plotname  
    # display $plotname &  
    
    plotname=${PLOTDIR}/talk_scores_kona3_${SUFFIX}.$PLOTEXT
    python3 tools/plot.py -d ${datafile}                    \
        -yc "scores"   -l "Max Outstanding Page Faults" \
        -xc ${XCOL} -xl "$XLABEL" ${XSTR} ${XMUL}           \
        -fs 15  -of $PLOTEXT  -o $plotname -yl "Count"   
    display $plotname &  

    # plotname=${PLOTDIR}/talk__${SUFFIX}.$PLOTEXT
    # python3 tools/plot.py -d ${datafile}                            \
    #     -yc "PERF_HANDLER_FAULT_Q" -l "1.0 Fault Queue Wait"        \
    #     -yc "PERF_HANDLER_RW" -l "1.1 Handle Fault" -ls solid       \
    #     -yc "PERF_PAGE_READ" -l "1.2 RDMA Read" -ls dashed          \
    #     -yc "PERF_HANDLER_MADV_NOTIF" -l "1.3 Handle Notif " -ls dashed     \
    #     -yc "PERF_POLLER_READ" -l "2   Handle Read" -ls solid       \
    #     -yc "PERF_POLLER_UFFD_COPY" -l "2.1 UFFD Copy" -ls dashed   \
    #     -yc "PERF_EVICT_TOTAL" -l "3   Evict Total" -ls solid       \
    #     -yc "PERF_EVICT_WP" -l "3.1 Evict WP" -ls dashed            \
    #     -yc "PERF_EVICT_WRITE" -l "3.2 Issue Write" -ls dashed      \
    #     -yc "PERF_EVICT_MADVISE" -l "3.3 Madvise" -ls dashed        \
    #     -xc ${XCOL} -xl "$XLABEL" ${XSTR} ${XMUL}                   \
    #     -yl "Micro-secs" --ymin 0 --ymax 300 --ymul 454e-6          \
    #     -fs 10  -of $PLOTEXT  -o $plotname -t "Kona Op Latencies"
    # display $plotname &  

elif [ "$PLOTSET" -eq 2 ]; then 
    plotname=${PLOTDIR}/talk_konamem_xput_${SUFFIX}.$PLOTEXT
    datafile_kona="temp_kona"
    sed '/NoKona/d' $datafile > $datafile_kona      #remove nokona run
    python3 tools/plot.py -d ${datafile}                \
        -yc achieved -l "Throughput" -ls solid          \
        -xc ${XCOL} -xl "$XLABEL" ${XSTR} ${XMUL}       \
        -yl "Million Ops/sec" --ymul 1e-6               \
        -fs 15 -of $PLOTEXT -o $plotname
    display $plotname &     
    display $plotname &   
fi

rm $datafile
rm temp_*
