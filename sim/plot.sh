#!/bin/bash
set -e

#
# Get results & charts for simulations
#

PLOTEXT=png
DATADIR=data
SCRIPT_DIR=`dirname "$0"`

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

    -id=*|--plotid=*)
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
HIT_RATIO=0.9
HIT_TIME_NS=1400
PF_TIME_NS=15000
UP_PF_TIME_NS=17000
NOUP_PF_TIME_NS=13500
KONA_PF_RATE=110000
UPTIME_NS=2500
TMP_FILE_PFX='tmp_sim_'
PLOTLIST=${TMP_FILE_PFX}plots

# point to last chart if not provided
if [ -z "$PLOTID" ]; then 
    PLOTID=`grep '"$PLOTID" == "."' $0 | wc -l`
    PLOTID=$((PLOTID-1))
fi

# setup
outdir=$DATADIR/$PLOTID
mkdir -p $outdir

## 1. model vs simulator, no upcalls, varying kona rate
if [ "$PLOTID" == "1" ]; then
    for krate in 30000 100000 500000; do 
        plotname=${outdir}/xput_noup_kr${krate}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            if [[ $FORCE ]]; then   #generate data
                for mode in "mod" "sim"; do 
                    gcc simulate.c -lpthread -o simulate $DEBUG_FLAG
                    for cores in 2 4 6 8; do
                        out=$outdir/xput_${mode}_${cores}_${krate}
                        echo "cores,hitratio,hitcost,pfcost,xput,faults" > $out
                        for hr in $(seq 0.5 0.1 1); do
                            if [ "$mode" == "mod" ]; then 
                                python model.py -c $cores -h1 $hr -th $HIT_TIME_NS \
                                    -tf $PF_TIME_NS -kr $krate  >> $out
                            else
                                echo "simulating $cores $krate" "$hr"
                                ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                    "$PF_TIME_NS" "$hr" 0 "" >> $out
                            fi
                        done
                    done
                done
            fi
            python3 ${SCRIPT_DIR}/../scripts/plot.py    \
                -xc hitratio -xl "Local Hit Ratio" -yc xput -yl "MOPS" --ymul 1e-6 \
                -d ${outdir}/xput_sim_2_${krate}    -l "2"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_2_${krate}    -l ""    -ls dashed  -cmi 1  \
                -d ${outdir}/xput_sim_4_${krate}    -l "4"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_4_${krate}    -l ""    -ls dashed  -cmi 1  \
                -d ${outdir}/xput_sim_6_${krate}    -l "6"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_6_${krate}    -l ""    -ls dashed  -cmi 1  \
                -d ${outdir}/xput_sim_8_${krate}    -l "8"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_8_${krate}    -l ""    -ls dashed  -cmi 1  \
                --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname -lt "App CPU"
        fi
        display $plotname & 
    done
fi

## 2. model vs simulator, with upcalls, varying kona rate
if [ "$PLOTID" == "2" ]; then
    for krate in 30000 100000 500000; do 
        plotname=${outdir}/xput_up_kr${krate}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            if [[ $FORCE ]]; then   #generate data
                for mode in "mod" "sim"; do 
                    gcc simulate.c -lpthread -o simulate $DEBUG_FLAG
                    for cores in 2 4 6 8; do
                        out=$outdir/xput_${mode}_${cores}_${krate}
                        echo "cores,hitratio,hitcost,pfcost,xput,faults" > $out
                        for hr in $(seq 0.5 0.1 1); do
                            if [ "$mode" == "mod" ]; then 
                                python model.py -c $cores -h1 $hr -th $HIT_TIME_NS \
                                    -tf $PF_TIME_NS -kr $krate -u -tu $UPTIME_NS >> $out
                            else
                                ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                    "$PF_TIME_NS" "$hr" 1 "$UPTIME_NS" | tee -a $out
                            fi
                        done
                    done
                done
            fi
            python3 ${SCRIPT_DIR}/../scripts/plot.py    \
                -xc hitratio -xl "Local Hit Ratio" -yc xput -yl "MOPS" --ymul 1e-6 \
                -d ${outdir}/xput_sim_2_${krate}    -l "2"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_2_${krate}    -l ""    -ls dashed  -cmi 1  \
                -d ${outdir}/xput_sim_4_${krate}    -l "4"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_4_${krate}    -l ""    -ls dashed  -cmi 1  \
                -d ${outdir}/xput_sim_6_${krate}    -l "6"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_6_${krate}    -l ""    -ls dashed  -cmi 1  \
                -d ${outdir}/xput_sim_8_${krate}    -l "8"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_8_${krate}    -l ""    -ls dashed  -cmi 1  \
                --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname -lt "App CPU"
        fi
        display $plotname & 
    done
fi

## 3. model vs simulator, varying  page fault latency
if [ "$PLOTID" == "3" ]; then
    for krate in 500000; do 
        plotname=${outdir}/xput_noup_kr${krate}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            if [[ $FORCE ]]; then   #generate data
                for mode in "mod" "sim"; do 
                    gcc simulate.c -lpthread -o simulate $DEBUG_FLAG
                    for cores in 2 4 6 8; do
                        out=$outdir/xput_${mode}_${cores}_${krate}
                        echo "cores,hitratio,hitcost,pfcost,xput,faults" > $out                        
                        for pfcost in $(seq 2000 3000 30000); do
                            if [ "$mode" == "mod" ]; then 
                                python model.py -c $cores -h1 $HIT_RATIO -th $HIT_TIME_NS \
                                    -tf $pfcost -kr $krate >> $out
                            else
                                ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                    "$pfcost" "$HIT_RATIO" 0 "" | tee -a $out
                            fi
                        done
                    done
                done
            fi
            python3 ${SCRIPT_DIR}/../scripts/plot.py  -xc pfcost \
                -xl "Fault cost (µs)" --xmul 1e-3 -yc xput -yl "MOPS" --ymul 1e-6 \
                -d ${outdir}/xput_sim_2_${krate}    -l "2"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_2_${krate}    -l ""    -ls dashed  -cmi 1  \
                -d ${outdir}/xput_sim_4_${krate}    -l "4"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_4_${krate}    -l ""    -ls dashed  -cmi 1  \
                -d ${outdir}/xput_sim_6_${krate}    -l "6"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_6_${krate}    -l ""    -ls dashed  -cmi 1  \
                -d ${outdir}/xput_sim_8_${krate}    -l "8"   -ls solid   -cmi 0  \
                -d ${outdir}/xput_mod_8_${krate}    -l ""    -ls dashed  -cmi 1  \
                --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname -lt "App CPU"
        fi
        display $plotname & 
    done
fi

## 4. simulation with and without upcalls, varying kona rate
if [ "$PLOTID" == "4" ]; then
    montagename=${outdir}/xput_up_noup.${PLOTEXT}
    # for krate in 30000 100000 500000; do 
    for krate in 125000; do 
        plotname=${outdir}/xput_up_noup_kr${krate}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            if [[ $FORCE ]]; then   #generate data
                for mode in "up" "noup"; do 
                    gcc simulate.c -lpthread -o simulate $DEBUG_FLAG
                    # for cores in 2 4 6 8; do
                    for cores in 1 2 3 4 5; do
                        out=$outdir/xput_${mode}_${cores}_${krate}
                        echo "cores,pfcost,hitratio,hitcost,xput1,xput,faults" > $out
                        realkrate=$krate
                        for hr in $(seq 0.5 0.1 1); do
                            if [ "$mode" == "noup" ]; then 
                                # if [[ $krate -eq 125000 ]]; then realkrate=110000;  fi  #to get closer to reality
                                ./simulate $cores "$realkrate" "$HIT_TIME_NS" \
                                    "$NOUP_PF_TIME_NS" "$hr" 0 "" | tee -a $out
                            else
                                # if [[ $krate -eq 125000 ]]; then realkrate=144000;  fi
                                ./simulate $cores "$realkrate" "$HIT_TIME_NS" \
                                    "$UP_PF_TIME_NS" "$hr" 1 "$UPTIME_NS" | tee -a $out
                            fi
                        done
                        echo realkrate: $realkrate
                    done
                done
            fi
            python3 ${SCRIPT_DIR}/../scripts/plot.py    \
                -xc hitratio -xl "Local Hit Ratio" -yc xput -yl "MOPS" --ymul 1e-6  \
                -d ${outdir}/xput_up_1_${krate}    -l "1"   -ls solid   -cmi 0      \
                -d ${outdir}/xput_noup_1_${krate}    -l ""    -ls dashed  -cmi 1    \
                -d ${outdir}/xput_up_2_${krate}    -l "2"   -ls solid   -cmi 0      \
                -d ${outdir}/xput_noup_2_${krate}    -l ""    -ls dashed  -cmi 1    \
                -d ${outdir}/xput_up_3_${krate}    -l "3"   -ls solid   -cmi 0      \
                -d ${outdir}/xput_noup_3_${krate}    -l ""    -ls dashed  -cmi 1    \
                -d ${outdir}/xput_up_4_${krate}    -l "4"   -ls solid   -cmi 0      \
                -d ${outdir}/xput_noup_4_${krate}    -l ""    -ls dashed  -cmi 1    \
                -d ${outdir}/xput_up_5_${krate}    -l "5"   -ls solid   -cmi 0      \
                -d ${outdir}/xput_noup_5_${krate}    -l ""    -ls dashed  -cmi 1    \
                -lt "App CPU" -t "Kona $((krate/1000))k"                          \
                --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname 
        fi
        files="$files $plotname"
    done
    montage -tile 0x1 -geometry +5+5 -border 5 $files ${montagename}
    display $montagename &
fi

## 5. two workloads with and without upcalls, varying workload hit ratios
if [ "$PLOTID" == "5" ]; then
    krate=500000
    for workloads in 0.5,0.9; do    # 0.5,0.5 0.9,0.9 0.5,0.9
        IFS=","; set -- $workloads; 
        HIT_R1=$1;      hitp1=`echo $HIT_R1 | awk '{ print $0*100 }'`;
        HIT_R2=$2;      hitp2=`echo $HIT_R2 | awk '{ print $0*100 }'`;
        montagename=${outdir}/xput_twodist_up_noup_${krate}_${hitp1}_${hitp2}.${PLOTEXT}
        for split in "no"; do     # "no" "yes"
            for switch in "no"; do  # "no" "yes"
                upfile=$outdir/xput_up_split_${split}_switch_${switch}_${krate}_${hitp1}_${hitp2}
                noupfile=$outdir/xput_noup_split_${split}_switch_${switch}_${krate}_${hitp1}_${hitp2}
                plotname=${outdir}/xput_up_noup_split_${split}_switch_${switch}_kr${krate}_${hitp1}_${hitp2}.${PLOTEXT}
                if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
                    if [[ $FORCE ]] || [ ! -f "$upfile" ]; then   #generate data
                        CFLAG1=
                        if [ "$split" == "yes" ]; then 
                            CFLAG1="-DSPLIT_CORES"
                        fi
                        CFLAG2=
                        if [ "$switch" == "yes" ]; then 
                            CFLAG2="-DSWITCH_ON_FAULT"
                        fi
                        echo gcc simulate.c -lpthread -o simulate ${DEBUG_FLAG} ${CFLAG1} ${CFLAG2}
                        gcc simulate.c -lpthread -o simulate ${DEBUG_FLAG} ${CFLAG1} ${CFLAG2}
                        header="cores,pfcost,hitratio1,hitcost1,xput1,hitratio2,hitcost2,xput2,xput,faults"
                        echo "$header" > $upfile
                        for cores in 2 4 6 8; do
                            ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                "$PF_TIME_NS" "$HIT_R1" 1 "$UPTIME_NS" "$HIT_R2" | tee -a $upfile   #upcalls
                        done
                        echo "$header" > $noupfile
                        for cores in 2 4 6 8; do
                            ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                "$PF_TIME_NS" "$HIT_R1" 0 "" "$HIT_R2" | tee -a $noupfile           #no upcalls
                        done
                    fi
                    python3 ${SCRIPT_DIR}/../scripts/plot.py -xc cores -xl "App CPU" \
                        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 4                    \
                        -dyc $upfile xput1   -l "h=${HIT_R1}"   -ls solid   -cmi 0  \
                        -dyc $noupfile xput1 -l ""              -ls dashed  -cmi 1  \
                        -dyc $upfile xput2   -l "h=${HIT_R2}"   -ls solid   -cmi 0  \
                        -dyc $noupfile xput2 -l ""              -ls dashed  -cmi 1  \
                        -dyc $upfile xput    -l "Total"         -ls solid   -cmi 0  \
                        -dyc $noupfile xput  -l ""              -ls dashed  -cmi 1  \
                        --size 4 3 -fs 11 -of $PLOTEXT -o $plotname
                fi
                echo $plotname >> $PLOTLIST
                plots="$plots -d $upfile -l $split$switch"
            done
        done
        montage -tile 0x2 -geometry +5+5 -border 5 @$PLOTLIST ${montagename}
        display $montagename &

        # # all aggregate xputs on one chart
        # plotname=${outdir}/xput_twodist_total_${krate}_${hitp1}_${hitp2}.${PLOTEXT}
        # python3 ${SCRIPT_DIR}/../scripts/plot.py   \
        #     -d data/5/xput_up_split_no_switch_no_${krate}_${hitp1}_${hitp2} -l "no no"     \
        #     -d data/5/xput_up_split_no_switch_yes_${krate}_${hitp1}_${hitp2} -l "no yes"   \
        #     -d data/5/xput_up_split_yes_switch_no_${krate}_${hitp1}_${hitp2} -l "yes no"   \
        #     -d data/5/xput_up_split_yes_switch_yes_${krate}_${hitp1}_${hitp2} -l "yes yes" \
        #     -xc cores -xl "App CPU" -yc xput                \
        #     -yl "Total MOPS" --ymul 1e-6 --ymin 0 --ymax 4      \
        #     --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname -lt "Split Switch"
        # display $plotname &
    done
fi

## 6. simulation with and without upcalls, varying servicing time
if [ "$PLOTID" == "6" ]; then
    krate=500000
    montagename=${outdir}/xput_up_noup_kr${krate}.${PLOTEXT}
    for hr in 0.5 0.9 0.99; do 
        hitp=`echo $hr | awk '{ print $0*100 }'`
        plotname=${outdir}/xput_up_noup_kr${krate}_hr${hitp}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            if [[ $FORCE ]]; then   #generate data
                for mode in "up" "noup"; do 
                    gcc simulate.c -lpthread -o simulate $DEBUG_FLAG
                    for cores in 2 4 6 8; do
                        out=$outdir/xput_${mode}_${cores}_${krate}_hr${hitp}
                        echo "cores,pfcost,hitratio,hitcost,xput1,xput,faults" > $out
                        for hittime in $(seq 500 400 10000); do
                            if [ "$mode" == "noup" ]; then 
                                ./simulate $cores "$krate" "$hittime" \
                                    "$PF_TIME_NS" "$hr" 0 "" | tee -a $out
                            else
                                ./simulate $cores "$krate" "$hittime" \
                                    "$PF_TIME_NS" "$hr" 1 "$UPTIME_NS" | tee -a $out
                            fi
                        done
                    done
                done
            fi
            python3 ${SCRIPT_DIR}/../scripts/plot.py    \
                -xc hitcost -xl "Service Time (ns)" -yc xput -yl "MOPS" --ymul 1e-6         \
                -d ${outdir}/xput_up_2_${krate}_hr${hitp}   -l "2"   -ls solid   -cmi 0     \
                -d ${outdir}/xput_noup_2_${krate}_hr${hitp} -l ""    -ls dashed  -cmi 1     \
                -d ${outdir}/xput_up_4_${krate}_hr${hitp}   -l "4"   -ls solid   -cmi 0     \
                -d ${outdir}/xput_noup_4_${krate}_hr${hitp} -l ""    -ls dashed  -cmi 1     \
                -d ${outdir}/xput_up_6_${krate}_hr${hitp}   -l "6"   -ls solid   -cmi 0     \
                -d ${outdir}/xput_noup_6_${krate}_hr${hitp} -l ""    -ls dashed  -cmi 1     \
                -d ${outdir}/xput_up_8_${krate}_hr${hitp}   -l "8"   -ls solid   -cmi 0     \
                -d ${outdir}/xput_noup_8_${krate}_hr${hitp} -l ""    -ls dashed  -cmi 1     \
                -lt "App CPU" -t "HitRatio $hr"                                             \
                --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname 
        fi
        echo $plotname >> $PLOTLIST
    done
    montage -tile 0x1 -geometry +5+5 -border 5 @$PLOTLIST ${montagename}
    display $montagename &
fi

## 6. simulation with and without upcalls, varying pf cost
if [ "$PLOTID" == "7" ]; then
    krate=500000
    for hr in 0.5 0.9 0.99; do 
        hitp=`echo $hr | awk '{ print $0*100 }'`
        plotname=${outdir}/xput_up_noup_kr${krate}_hr${hitp}.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            if [[ $FORCE ]]; then   #generate data
                for mode in "up" "noup"; do 
                    gcc simulate.c -lpthread -o simulate $DEBUG_FLAG
                    for cores in 2 4 6 8; do
                        out=$outdir/xput_${mode}_${cores}_${krate}_hr${hitp}
                        echo "cores,pfcost,hitratio,hitcost,xput1,xput,faults" > $out
                        for pfcost in $(seq 5000 5000 50000); do
                            if [ "$mode" == "noup" ]; then 
                                ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                    "$pfcost" "$hr" 0 "" | tee -a $out
                            else
                                ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                    "$pfcost" "$hr" 1 "$UPTIME_NS" | tee -a $out
                            fi
                        done
                    done
                done
            fi
            python3 ${SCRIPT_DIR}/../scripts/plot.py    \
                -xc pfcost -xl "PF Time (µs)" -yc xput -yl "MOPS" --ymul 1e-6 --xmul 1e-3   \
                -d ${outdir}/xput_up_2_${krate}_hr${hitp}   -l "2"   -ls solid   -cmi 0     \
                -d ${outdir}/xput_noup_2_${krate}_hr${hitp} -l ""    -ls dashed  -cmi 1     \
                -d ${outdir}/xput_up_4_${krate}_hr${hitp}   -l "4"   -ls solid   -cmi 0     \
                -d ${outdir}/xput_noup_4_${krate}_hr${hitp} -l ""    -ls dashed  -cmi 1     \
                -d ${outdir}/xput_up_6_${krate}_hr${hitp}   -l "6"   -ls solid   -cmi 0     \
                -d ${outdir}/xput_noup_6_${krate}_hr${hitp} -l ""    -ls dashed  -cmi 1     \
                -d ${outdir}/xput_up_8_${krate}_hr${hitp}   -l "8"   -ls solid   -cmi 0     \
                -d ${outdir}/xput_noup_8_${krate}_hr${hitp} -l ""    -ls dashed  -cmi 1     \
                --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname 
        fi
        display $plotname &
    done
fi

# cleanup
rm -f ${TMP_FILE_PFX}*