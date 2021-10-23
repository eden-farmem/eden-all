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

# # MEMCACHED MEM ACCESS
# expname="run-10-17-21-19"     # .001 Mpps
expname="run-10-19-13-22"       # 2 Mpps
python ${SCRIPT_DIR}/parse_addr_data.py -n ${expname}

DATADIR=data/$expname/addrs/
PLOTDIR=data/$expname/plots
mkdir -p $PLOTDIR

# datafile=${DATADIR}/rfaults
# plotname=${PLOTDIR}/rfaults.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -d ${datafile}        \
#     -yc addr -yl "Address" -xc "time"               \
#     --size 8 4 -of $PLOTEXT -o $plotname --xmin 40 --xmax 90
# display $plotname &

# datafile=${DATADIR}/wfaults
# plotname=${PLOTDIR}/wfaults.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -d ${datafile}        \
#     -yc addr -yl "Address" -xc "time"               \
#     --size 8 4 -of $PLOTEXT -o $plotname --xmin 40 --xmax 90
# display $plotname &

# datafile=${DATADIR}/rfaults
# plotname=${PLOTDIR}/rfaults-offset.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -d ${datafile}        \
#     -yc pgofst -yl "Offset in Page" -xc "time"      \
#     --size 8 4 -of $PLOTEXT -o $plotname --xmin 40 --xmax 90
# display $plotname &

# datafile=${DATADIR}/wfaults
# plotname=${PLOTDIR}/wfaults-offset.${PLOTEXT}
# python3 ${SCRIPT_DIR}/plot.py -d ${datafile}        \
#     -yc pgofst -yl "Offset in Page" -xc "time"      \
#     --size 8 4 -of $PLOTEXT -o $plotname --xmin 40 --xmax 90
# display $plotname &

datafile=${DATADIR}/counts
plotname=${PLOTDIR}/counts.${PLOTEXT}
python3 ${SCRIPT_DIR}/plot.py -d ${datafile}        \
    -yc rfaults -yc wfaults -xc "time"              \
    --size 8 4 -of $PLOTEXT -o $plotname --xmin 30 --xmax 90
display $plotname &



############# ARCHIVED ##############################

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


