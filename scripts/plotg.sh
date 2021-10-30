#!/bin/bash
set -e 
#
# Plot/compare stats across multiple groups of runs
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
SCRIPT_DIR=`dirname "$0"`
TMPFILE_PFX="temp_plotg_"

usage="\n
-s1,  --suffix1   \t a plain suffix defining the first group of runs\n
-cs1, --csuffix1  \t same as -s1 but a more complex one (with regexp pattern)\n
-l1,  --label1    \t plot label for first group of runs\n
-s[234],  --suffix[234] \t a plain suffix defining the group [234] of runs (optional)\n
-cs[234], --csuffix[234]  \t same as -s[234] but a more complex one (with regexp pattern)\n
-l2,  --label2    \t plot label for second group of runs\n
-vm,  --vary-mem  \t hint to use kona memory on x-axis (default)\n
-vc,  --vary-cores \t hint to use server cores on x-axis\n
-d,   --display   \t display individal plots\n
-f,   --force     \t force re-summarize results\n"

# Defaults
XCOL=konamem
XLABEL='Local Mem (MB)'
COLIDX=3
LTITLE=""

# Read parameters
for i in "$@"
do
case $i in
    -s1=*|--suffix1=*)
    SUFFIX1="${i#*=}"
    ;;

    -cs1=*|--csuffix1=*)
    CSUFFIX1="${i#*=}"
    ;;
    
    -l1=*|--label1=*)
    LABEL1="${i#*=}"
    ;;

    -cs1=*|--csuffix1=*)
    CSUFFIX1="${i#*=}"
    ;;

    -s2=*|--suffix2=*)
    SUFFIX2="${i#*=}"
    ;;

    -l2=*|--label2=*)
    LABEL2="${i#*=}"
    ;;

    -cs2=*|--csuffix2=*)
    CSUFFIX2="${i#*=}"
    ;;
    
    -s3=*|--suffix3=*)
    SUFFIX3="${i#*=}"
    ;;

    -l3=*|--label3=*)
    LABEL3="${i#*=}"
    ;;

    -cs3=*|--csuffix3=*)
    CSUFFIX3="${i#*=}"
    ;;

    -s4=*|--suffix4=*)
    SUFFIX4="${i#*=}"
    ;;

    -l4=*|--label4=*)
    LABEL4="${i#*=}"
    ;;

    -cs4=*|--csuffix4=*)
    CSUFFIX4="${i#*=}"
    ;;

    -lt=*|--label-title=*)
    LTITLE="${i#*=}"
    ;;

    -d|--display)
    DISPLAY_EACH=1
    ;;

    -f|--force)
    FORCE=1
    ;;

    -vm|--vary-mem)
    XCOL=konamem
    XLABEL='Local Mem (MB)'
    COLIDX=3
    ;;

    -vc|--vary-cores)
    XCOL=scores
    XLABEL='Server Cores'
    COLIDX=4
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

if [[ ! $SUFFIX1 ]] && [[ ! $CSUFFIX1 ]]; then echo "must provide -s1/-cs1"; echo -e $usage; exit 1; fi
# if [[ ! $SUFFIX2 ]] && [[ ! $CSUFFIX2 ]]; then echo "must provide -s2/-cs2"; echo -e $usage; exit 1; fi
LABEL1=${LABEL1:-$SUFFIX1};  LABEL1=${LABEL1:-$CSUFFIX1}
LABEL2=${LABEL2:-$SUFFIX2};  LABEL2=${LABEL2:-$CSUFFIX2}
LABEL3=${LABEL3:-$SUFFIX3};  LABEL3=${LABEL3:-$CSUFFIX3}

# Prepare data for each group
parse_runs_prepare_data() {
    SUFFIX=$1
    CSUFFIX=$2
    OUTFILE=$3
    FORCE=$4

    if [[ $SUFFIX ]]; then 
        LS_CMD=`ls -d1 data/run-${SUFFIX}*/`
        SUFFIX=$SUFFIX
    elif [[ $CSUFFIX ]]; then
        LS_CMD=`ls -d1 data/*/ | grep -e "$CSUFFIX"`
        SUFFIX=$CSUFFIX
    fi

    stats=
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
            python ${SCRIPT_DIR}/summary.py -n $name --lat --kona --app --iok
        fi
        
        # aggregate across runs
        header=nconns,mpps,konamem,scores,`cat $statfile | awk 'NR==1'`
        curstats=`cat $statfile | awk 'NR==2'`
        # if ! [[ $curstats ]]; then    curstats=$prevstats;  fi      #HACK!
        stats="$stats\n$nconns,$mpps,$konamem_mb,$sthreads,$curstats"
        prevstats=$curstats
    done

    # Data in one file
    echo ${OUTFILE}
    echo -e "$stats" > $OUTFILE
    sort -k${COLIDX} -n -t, $OUTFILE -o $OUTFILE
    sed -i "1s/^/$header/" $OUTFILE
    sed -i "s/$SOME_BIG_NUMBER/NoKona/" $OUTFILE
    cat $OUTFILE
}

# Group 1
tmpfile1=${TMPFILE_PFX}1
parse_runs_prepare_data "$SUFFIX1" "$CSUFFIX1" "$tmpfile1" "$FORCE"
datapoints1=$(wc -l < $tmpfile1)
plots="$plots -d $tmpfile1 -l """""$LABEL1""""
fsuffix=${SUFFIX1:-$CSUFFIX1}

# Add other groups
add_plot_group() {
    local GID=$1
    local SUFFIX=$2
    local CSUFFIX=$3
    local LABEL=$4
    local FORCE=$5
    local tmpfile=${TMPFILE_PFX}${GID}
    if [[ $SUFFIX ]] || [[ $CSUFFIX ]]; then
        parse_runs_prepare_data "$SUFFIX" "$CSUFFIX" "$tmpfile" "$FORCE"
        local dps=$(wc -l < $tmpfile)
        if [ $datapoints1 != $dps ]; then 
            echo "ERROR! group ${GID} has different number of runs/data points"; 
            exit 1; 
        fi
        plots="$plots -d $tmpfile -l """""$LABEL""""
        fsuffix="${fsuffix}__${SUFFIX:-$CSUFFIX}"
    fi
}

add_plot_group 2 "$SUFFIX2" "$CSUFFIX2" "$LABEL2" "$FORCE"
add_plot_group 3 "$SUFFIX3" "$CSUFFIX3" "$LABEL3" "$FORCE"
add_plot_group 4 "$SUFFIX4" "$CSUFFIX4" "$LABEL4" "$FORCE"

# # Group 2
# tmpfile2=${TMPFILE_PFX}2
# parse_runs_prepare_data "$SUFFIX2" "$CSUFFIX2" "$tmpfile2" "$FORCE"
# lines2=$(wc -l < $tmpfile2)
# echo $lines1. $lines2
# if [ $lines1 != $lines2 ]; then 
#     echo "ERROR! groups 1 and 2 have different number of runs"; 
#     exit 1; 
# fi
# plots="$plots -d $tmpfile2 -l ""'""$LABEL2""'"
# fsuffix="${fsuffix}__${SUFFIX2:-$CSUFFIX2}"

# # Group 3
# tmpfile3=${TMPFILE_PFX}3
# if [[ $SUFFIX3 ]] || [[ $CSUFFIX3 ]]; then
#     parse_runs_prepare_data "$SUFFIX3" "$CSUFFIX3" "$tmpfile3" "$FORCE"
#     lines3=$(wc -l < $tmpfile3)
#     if [ $lines1 != $lines3 ]; then 
#         echo "ERROR! group 3 has different number of runs"; 
#         exit 1; 
#     fi
#     plots="$plots -d $tmpfile3 -l ""'"$LABEL3"'"
#     fsuffix="${fsuffix}__${SUFFIX3:-$CSUFFIX3}"
# fi

# # Group 4
# tmpfile4=${TMPFILE_PFX}4
# if [[ $SUFFIX3 ]] || [[ $CSUFFIX3 ]]; then
#     parse_runs_prepare_data "$SUFFIX3" "$CSUFFIX3" "$tmpfile3" "$FORCE"
#     lines3=$(wc -l < $tmpfile3)
#     if [ $lines1 != $lines3 ]; then 
#         echo "ERROR! group 3 has different number of runs"; 
#         exit 1; 
#     fi
#     plots="$plots -d $tmpfile3 -l ""'"$LABEL3"'"
#     fsuffix="${fsuffix}__${SUFFIX3:-$CSUFFIX3}"
# fi

# Plot memcached
plotname=${PLOTDIR}/memcached_xput_${fsuffix}.$PLOTEXT
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
    python3 ${SCRIPT_DIR}/plot.py ${plots}                          \
        -yc achieved -ls solid -yl "Xput Mops/sec" --ymul 1e-6      \
        -xc $XCOL -xl "$XLABEL" --ylog                              \
         --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname -lt "$LTITLE"
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

# Plot kona 
plotname=${PLOTDIR}/konastats_${fsuffix}.$PLOTEXT
ycol="n_faults"     # options: "malloc_size" "n_net_page_in" "n_net_page_out" "outstanding"
ydesc="Kilo Page Faults / sec"
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
    # sed '/NoKona/d' $datafile > $datafile_kona      #remove nokona run
    python3 ${SCRIPT_DIR}/plot.py ${plots}                          \
        -yc $ycol -ls solid -yl "$ydesc" --ymul 1e-3                \
        -xc $XCOL -xl "$XLABEL"                                     \
         --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname -lt "$LTITLE"
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

plotname=${PLOTDIR}/konastats1_${fsuffix}.$PLOTEXT
ycol="mem_pressure"     # options: "malloc_size" "n_net_page_in" "n_net_page_out" "outstanding"
ydesc="Mem Pressure (GB)"
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
    # sed '/NoKona/d' $datafile > $datafile_kona      #remove nokona run
    python3 ${SCRIPT_DIR}/plot.py ${plots}                      \
        -yc $ycol -ls solid -yl "$ydesc" --ymul 1e-9            \
        -xc $XCOL -xl "$XLABEL"                                 \
         --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname -lt "$LTITLE"
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

plotname=${PLOTDIR}/konastats_extended_${fsuffix}.$PLOTEXT
ycol="PERF_HANDLER_FAULT_Q"     # options: "PERF_EVICT_MADVISE", "PERF_EVICT_TOTAL"
ydesc="Fault Wait Time (µs)"
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
    python3 ${SCRIPT_DIR}/plot.py ${plots}              \
        -yc $ycol -yl "$ydesc"  --ymul 454e-6           \
        -xc $XCOL -xl "$XLABEL"                         \
         --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname -lt "$LTITLE" 
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

plotname=${PLOTDIR}/konastats_extended1_${fsuffix}.$PLOTEXT
ycol="PERF_EVICT_TOTAL"     # options: "PERF_EVICT_MADVISE", "PERF_EVICT_TOTAL"
ydesc="Eviction Time (µs)"
if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
    python3 ${SCRIPT_DIR}/plot.py ${plots}                  \
        -yc $ycol -yl "$ydesc" --ymin 0  --ymul 454e-6      \
        -xc $XCOL -xl "$XLABEL"                             \
         --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname -lt "$LTITLE"
    if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
fi
files="$files $plotname"

# # Plot iok stats
# plotname=${PLOTDIR}/iokstats_${SUFFIX}.$PLOTEXT
# if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
#     python3 ${SCRIPT_DIR}/plot.py -d ${datafile}                        \
#         -yc "TX_PULLED" -l "From Runtime" -ls solid                     \
#         -yc "RX_PULLED" -l "To Runtime" -ls solid                       \
#         -yc "RX_UNICAST_FAIL" -l "To Runtime (Failed)" -ls solid        \
#         -yc "IOK_SATURATION" -l "Core Saturation" -ls dashed            \
#         -xc $XCOL -xl "$XLABEL"                                   \
#         -yl "Million pkts/sec" --ymul 1e-6 --ymin 0                     \
#         --twin 4  -tyl "Saturation %" --tymul 100 --tymin 0 --tymax 110 \
#          --size 4.5 3 -fs 11 -of $PLOTEXT  -o $plotname -lt "Shenango I/O Core"
#     if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
# fi
# files="$files $plotname"

# # Plot runtime stats
# plotname=${PLOTDIR}/${name}_runtime.$PLOTEXT
# if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
#     python3 ${SCRIPT_DIR}/plot.py -d ${datafile}                \
#         -yc "rxpkt" -l "From I/O Core" -ls solid                \
#         -yc "txpkt" -l "To I/O Core" -ls solid                  \
#         -yc "drops" -l "Pkt drops" -ls solid                    \
#         -yc "cpupct" -l "CPU Utilization" -ls dashed            \
#         -xc $XCOL -xl "$XLABEL"                           \
#         -yl "Million pkts/sec" --ymul 1e-6 --ymin 0             \
#         --twin 4  -tyl "CPU Cores" --tymul 1e-2 --tymin 0       \
#          --size 4.5 3 -fs 11  -of $PLOTEXT  -o $plotname -lt "Shenango Resources"
#     if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
# fi
# files="$files $plotname"

# plotname=${PLOTDIR}/${name}_scheduler.$PLOTEXT
# if [[ $FORCE ]] || [ ! -f "$plotname" ]; then
#     python3 ${SCRIPT_DIR}/plot.py -d ${datafile}                        \
#         -yc "stolenpct" -l "Stolen Work %" -ls solid            \
#         -yc "migratedpct" -l "Core Migration %" -ls solid       \
#         -yc "localschedpct" -l "Core Local Work %" -ls solid    \
#         -yc "rescheds" -l "Reschedules" -ls dashed              \
#         -yc "parks" -l "KThread Parks" -ls dashed               \
#         -xc $XCOL -xl "$XLABEL"                           \
#         -yl "Percent" --ymin 0 --ymax 110                       \
#         --twin 4  -tyl "Million Times" --tymul 1e-6 --tymin 0   \
#          --size 4.5 3 -fs 11  -of $PLOTEXT  -o $plotname -lt "Shenango Scheduler" 
#     if [[ $DISPLAY_EACH ]]; then display $plotname &    fi
# fi
# files="$files $plotname"

# # # Combine
# # echo $files
plotname=${PLOTDIR}/all_${fsuffix}.$PLOTEXT
montage -tile 0x2 -geometry +5+5 -border 5 $files ${plotname}
display ${plotname} &
rm ${TMPFILE_PFX}*
