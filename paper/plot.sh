#!/bin/bash
set -e

#
# Plot figures for the paper
#

PLOTEXT=png
SCRIPT_DIR=`dirname "$0"`
PLOTDIR=${SCRIPT_DIR}/plots

usage="\n
-f,   --force \t\t force re-summarize data and re-generate plots\n
-fp,  --force-plots \t force re-generate just the plots\n
-id,  --plotid \t pick one of the many charts this script can generate\n
-d,  --debug \t run programs in debug mode where applies\n
-h, --help \t\t this usage information message\n"

for i in "$@"
do
case $i in
    -f|--force)
    FORCE=1
    FORCE_PLOTS=1
    ;;
    
    -fp|--force-plots)
    FORCE_PLOTS=1
    ;;

    -id=*|--fig=*|--plotid=*)
    PLOTID="${i#*=}"
    ;;
    
    -d|--debug)
    DEBUG=1
    DEBUG_FLAG="-DDEBUG"
    ;;

    *)          # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

#Defaults
TMP_FILE_PFX='tmp_paper_'
PLOTLIST=${TMP_FILE_PFX}plots

# point to last chart if not provided
if [ -z "$PLOTID" ]; then 
    PLOTID=`grep '"$PLOTID" == "."' $0 | wc -l`
    PLOTID=$((PLOTID-1))
fi

# setup
DATADIR=${SCRIPT_DIR}/$PLOTID
mkdir -p $PLOTDIR

## Figure 1: memcached - effect of lru on fault type
## Data
# cat ./data/run-03-26-00-07/stats/stat.csv |  awk -F, '{ print $20,$34 }'
# cat ./data/run-03-26-17-22/stats/stat.csv |  awk -F, '{ print $20,$34 }'
# legend loc: loc="lower left", bbox_to_anchor=(-.5, 1, 1, 0.8), ncol=1
if [ "$PLOTID" == "1" ]; then
    plotname=${PLOTDIR}/fig${PLOTID}_mcached.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py    \
            -d ${DATADIR}/data -z barstacked        \
            -yc kernel -l "Kernel"                  \
            -yc sched  -l "Scheduler"               \
            -xc "type" -xl " " -yl "% faults" -ll topout  \
            --size 2 4 -fs 12 -of $PLOTEXT -o $plotname -ll topout
    fi
    display $plotname & 
fi

## Figure 2: memcached - effect of no-refcount on fault kind
## Data
# cat data/run-10-28-12-38/stats/stat.csv | awk -F, '{ print $20,$21,$22,$29 }'
# cat data/run-11-29-18-28/stats/stat.csv | awk -F, '{ print $20,$21,$22,$29 }'
# legend loc: loc="lower left", bbox_to_anchor=(-.5, 1, 1, 0.8), ncol=1
if [ "$PLOTID" == "2" ]; then
    plotname=${PLOTDIR}/fig${PLOTID}_mcached.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py    \
            -d ${DATADIR}/data -z barstacked        \
            -yc read -l "Read"                      \
            -yc write  -l "Write"                   \
            -yc wprotect  -l "Wprotect"             \
            -xc "type" -xl " " -yl "% faults"       \
            --size 2 4 -fs 12 -of $PLOTEXT -o $plotname -ll topout
    fi
    display $plotname & 
fi



## Figure 3: memcached - overall performance kernel vs scheduler faults
## Data
# bash scripts/plotg.sh -s1="03-25-23" -l1="1" -s2="03-26-00" -l2="2"                 \
#     -s3="03-26-01-[0123]" -l3="3" -cs4="run-03-26-\(01-[45]\|02-[012]\)" -l4="4"    \
#     -cs5="run-03-26-\(02-[345]\|03-[01]\)" -l5="5" -s6="03-29-1[67]" -l6="6" -lt="App CPU (KERNEL)" -of=paper/3/kernel
# bash scripts/plotg.sh -s1="03-26-09-[0-5]" -l1="1" -s2="03-26-10-[0-3]" -l2="2"     \
#     -cs3="run-03-26-\(10-[45]\|11-[012]\)" -l3="3" -s5="03-26-12-[2-5]" -l5="5"     \
#     -cs4="run-03-26-\(11-[345]\|12-[01]\)" -l4="4" -s6="03-29-22" -l6="6" -lt="App CPU (SYNC)" -of=paper/3/sync
# bash scripts/plotg.sh -cs1="run-03-26-\(16-[345]\|17-[01]\)" -l1="1"                \
#     -s2="03-26-17-[2345]" -l2="2" -s3="03-26-18" -l3="3" -s4="03-27-14-[0123]"       \
#     -l4="4" -cs5="run-03-27-\(14-[45]\|15\)" -l5="5" -s6="03-30-[01]" -l6="6" -lt="App CPU (ASYNC)" -of=paper/3/async
if [ "$PLOTID" == "3" ]; then
    plotname=${PLOTDIR}/fig${PLOTID}_xput_kernel.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py                \
            -yc achieved -yl "MOPS" --ymul 1e-6    \
            -xc konamem  -xl "Local Hit Ratio" --xmul 5e-4      \
            -d ${PLOTID}/kernel_1.dat   -l "1" -ls dashed       \
            -d ${PLOTID}/kernel_2.dat   -l "2" -ls dashed       \
            -d ${PLOTID}/kernel_3.dat   -l "3" -ls dashed       \
            -d ${PLOTID}/kernel_4.dat   -l "4" -ls dashed       \
            -d ${PLOTID}/kernel_5.dat   -l "5" -ls dashed       \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
            display $plotname & 
    fi

    plotname=${PLOTDIR}/fig${PLOTID}_xput_scheduler.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py                \
            -yc achieved -yl "MOPS" --ymul 1e-6    \
            -xc konamem  -xl "Local Hit Ratio" --xmul 5e-4      \
            -d ${PLOTID}/async_1.dat   -l "1" -ls solid         \
            -d ${PLOTID}/async_2.dat   -l "2" -ls solid         \
            -d ${PLOTID}/async_3.dat   -l "3" -ls solid         \
            -d ${PLOTID}/async_4.dat   -l "4" -ls solid         \
            -d ${PLOTID}/async_5.dat   -l "5" -ls solid         \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
            display $plotname & 
    fi

    # compute xput gain
    for cores in 1 2 3 4 5; do
        cat ${PLOTID}/kernel_${cores}.dat | awk -F, '{ print $3 }' | tail -n +2 > tmp_konamem
        cat ${PLOTID}/kernel_${cores}.dat | awk -F, '{ print $13 }' | tail -n +2 > tmp_kernel
        cat ${PLOTID}/async_${cores}.dat | awk -F, '{ print $13 }' | tail -n +2 > tmp_sched
        paste tmp_kernel tmp_sched | awk '{ printf("%.2lf\n",$2/$1) }' > tmp_gain
        { echo -e "konamem,gain";  paste -d, tmp_konamem tmp_gain; } > ${PLOTID}/gain_${cores}.dat
        rm -f tmp_*
    done

    plotname=${PLOTDIR}/fig${PLOTID}_xput_gain.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py            \
            -yc gain -yl "Gain"                             \
            -xc konamem  -xl "Local Hit Ratio" --xmul 5e-4  \
            -d ${PLOTID}/gain_1.dat   -l "1" -ls solid    \
            -d ${PLOTID}/gain_2.dat   -l "2" -ls solid    \
            -d ${PLOTID}/gain_3.dat   -l "3" -ls solid    \
            -d ${PLOTID}/gain_4.dat   -l "4" -ls solid    \
            -d ${PLOTID}/gain_5.dat   -l "5" -ls solid    \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
        display $plotname & 
    fi

    plotname=${PLOTDIR}/fig${PLOTID}_faults_kernel.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py                \
            -yc n_faults -yl "Faults (MOPS)" --ymul 1e-6        \
            --ymin 0 --ymax 0.15                                \
            -xc konamem  -xl "Local Hit Ratio" --xmul 5e-4      \
            -d ${PLOTID}/kernel_1.dat   -l "1" -ls dashed       \
            -d ${PLOTID}/kernel_2.dat   -l "2" -ls dashed       \
            -d ${PLOTID}/kernel_3.dat   -l "3" -ls dashed       \
            -d ${PLOTID}/kernel_4.dat   -l "4" -ls dashed       \
            -d ${PLOTID}/kernel_5.dat   -l "5" -ls dashed       \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
            display $plotname & 
    fi

    plotname=${PLOTDIR}/fig${PLOTID}_faults_scheduler.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${SCRIPT_DIR}/../scripts/plot.py                \
            -yc n_faults -yl "Faults (MOPS)" --ymul 1e-6        \
            --ymin 0 --ymax 0.15                                \
            -xc konamem  -xl "Local Hit Ratio" --xmul 5e-4      \
            -d ${PLOTID}/async_1.dat   -l "1" -ls solid         \
            -d ${PLOTID}/async_2.dat   -l "2" -ls solid         \
            -d ${PLOTID}/async_3.dat   -l "3" -ls solid         \
            -d ${PLOTID}/async_4.dat   -l "4" -ls solid         \
            -d ${PLOTID}/async_5.dat   -l "5" -ls solid         \
            --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
            display $plotname & 
    fi
fi

## Figure 4: simulations - overall performance kernel vs scheduler faults with higher kona rate
## Data
# bash sim/plot.sh -id=4 -f and data in sim/data/4/xput_*_50000
if [ "$PLOTID" == "4" ]; then
    mkdir -p ${DATADIR}
    PFRATE=500000
    for PFRATE in 125000 250000 500000; do 
        cp ${SCRIPT_DIR}/../sim/data/4/xput_*_${PFRATE} ${DATADIR}/
        # plotname=${PLOTDIR}/fig${PLOTID}_sim_xput_kernel.${PLOTEXT}
        # if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        #     python3 ${SCRIPT_DIR}/../scripts/plot.py                    \
        #         -yc xput -yl "MOPS" --ymul 1e-6                         \
        #         -xc hitratio  -xl "Local Hit Ratio"                     \
        #         -d ${PLOTID}/xput_noup_1_${PFRATE}   -l "1" -ls dashed  \
        #         -d ${PLOTID}/xput_noup_2_${PFRATE}   -l "2" -ls dashed  \
        #         -d ${PLOTID}/xput_noup_3_${PFRATE}   -l "3" -ls dashed  \
        #         -d ${PLOTID}/xput_noup_4_${PFRATE}   -l "4" -ls dashed  \
        #         -d ${PLOTID}/xput_noup_5_${PFRATE}   -l "5" -ls dashed  \
        #         --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
        #         display $plotname & 
        # fi

        # plotname=${PLOTDIR}/fig${PLOTID}_sim_xput_scheduler.${PLOTEXT}
        # if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        #     python3 ${SCRIPT_DIR}/../scripts/plot.py                \
        #         -yc xput -yl "MOPS" --ymul 1e-6                     \
        #         -xc hitratio  -xl "Local Hit Ratio"                 \
        #         -d ${PLOTID}/xput_up_1_${PFRATE}   -l "1" -ls solid \
        #         -d ${PLOTID}/xput_up_2_${PFRATE}   -l "2" -ls solid \
        #         -d ${PLOTID}/xput_up_3_${PFRATE}   -l "3" -ls solid \
        #         -d ${PLOTID}/xput_up_4_${PFRATE}   -l "4" -ls solid \
        #         -d ${PLOTID}/xput_up_5_${PFRATE}   -l "5" -ls solid \
        #         --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
        #         display $plotname & 
        # fi

        # compute xput gain
        for cores in 1 2 3 4 5; do
            cat ${PLOTID}/xput_noup_${cores}_${PFRATE} | awk -F, '{ print $3 }' | tail -n +2 > tmp_hitr
            cat ${PLOTID}/xput_noup_${cores}_${PFRATE} | awk -F, '{ print $6 }' | tail -n +2 > tmp_kernel
            cat ${PLOTID}/xput_up_${cores}_${PFRATE}   | awk -F, '{ print $6 }' | tail -n +2 > tmp_sched
            paste tmp_kernel tmp_sched | awk '{ printf("%.2lf\n",$2/$1) }' > tmp_gain
            { echo -e "hitratio,gain";  paste -d, tmp_hitr tmp_gain; } > ${PLOTID}/gain_${PFRATE}_${cores}.dat
            rm -f tmp_*
        done

        plotname=${PLOTDIR}/fig${PLOTID}_xput_gain_${PFRATE}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            python3 ${SCRIPT_DIR}/../scripts/plot.py            \
                -yc gain -yl "Gain"                             \
                -xc hitratio  -xl "Local Hit Ratio"             \
                -d ${PLOTID}/gain_${PFRATE}_1.dat   -l "1" -ls solid      \
                -d ${PLOTID}/gain_${PFRATE}_2.dat   -l "2" -ls solid      \
                -d ${PLOTID}/gain_${PFRATE}_3.dat   -l "3" -ls solid      \
                -d ${PLOTID}/gain_${PFRATE}_4.dat   -l "4" -ls solid      \
                -d ${PLOTID}/gain_${PFRATE}_5.dat   -l "5" -ls solid      \
                --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
            display $plotname & 
        fi

        # plotname=${PLOTDIR}/fig${PLOTID}_faults_kernel.${PLOTEXT}
        # if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        #     python3 ${SCRIPT_DIR}/../scripts/plot.py                \
        #         -yc faults -yl "Faults (MOPS)" --ymul 1e-6          \
        #         -xc hitratio  -xl "Local Hit Ratio"                 \
        #         --ymin 0 --ymax 0.5                                 \
        #         -d ${PLOTID}/xput_noup_1_${PFRATE}   -l "1" -ls dashed  \
        #         -d ${PLOTID}/xput_noup_2_${PFRATE}   -l "2" -ls dashed  \
        #         -d ${PLOTID}/xput_noup_3_${PFRATE}   -l "3" -ls dashed  \
        #         -d ${PLOTID}/xput_noup_4_${PFRATE}   -l "4" -ls dashed  \
        #         -d ${PLOTID}/xput_noup_5_${PFRATE}   -l "5" -ls dashed  \
        #         --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
        #         display $plotname & 
        # fi

        # plotname=${PLOTDIR}/fig${PLOTID}_faults_scheduler.${PLOTEXT}
        # if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        #     python3 ${SCRIPT_DIR}/../scripts/plot.py                \
        #         -yc faults -yl "Faults (MOPS)" --ymul 1e-6          \
        #         --ymin 0 --ymax 0.5                                 \
        #         -xc hitratio  -xl "Local Hit Ratio"                 \
        #         -d ${PLOTID}/xput_up_1_${PFRATE}   -l "1" -ls solid \
        #         -d ${PLOTID}/xput_up_2_${PFRATE}   -l "2" -ls solid \
        #         -d ${PLOTID}/xput_up_3_${PFRATE}   -l "3" -ls solid \
        #         -d ${PLOTID}/xput_up_4_${PFRATE}   -l "4" -ls solid \
        #         -d ${PLOTID}/xput_up_5_${PFRATE}   -l "5" -ls solid \
        #         --size 4.5 3 -fs 12 -of $PLOTEXT -o $plotname -lt "CPU Cores"
        #         display $plotname & 
        # fi
    done
fi

# cleanup
rm -f ${TMP_FILE_PFX}*