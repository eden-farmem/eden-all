#!/bin/bash
set -e

# Miscellaneous plots

PLOTEXT=png
PLOTDIR=plots/
DATADIR=data/
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
PF_TIME_US=18500
KONA_PF_RATE=110000
UPTIME_NS=4000

# point to last chart if not provided
if [ -z "$PLOTID" ]; then 
    PLOTID=`grep '"$PLOTID" == "."' $0 | wc -l`
    PLOTID=$((PLOTID-1))
fi

## 1. model vs simulator, no upcalls, varying kona rate
if [ "$PLOTID" == "1" ]; then
    outdir=$DATADIR/$PLOTID/
    mkdir -p $outdir
    for krate in 30000 100000 500000; do 
        plotname=${outdir}/xput_noup_kr${krate}.${PLOTEXT}
        if [[ $FORCE ]] || [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            if [[ $FORCE ]]; then   #generate data
                for mode in "mod" "sim"; do 
                    gcc simulate.c -lpthread -o simulate $DEBUG_FLAG
                    for cores in 2 4 6 8; do
                        out=$outdir/xput_${mode}_${cores}_${krate}
                        echo "cores,hitratio,hitcost,pfcost,xput,faults" > $out
                        for hr in $(seq 0.5 0.1 1); do
                            if [ "$mode" == "mod" ]; then 
                                python model.py -c $cores -h1 $hr -th $HIT_TIME_NS \
                                    -tf $PF_TIME_US -kr $krate  >> $out
                            else
                                echo "simulating $cores $krate" "$hr"
                                ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                    "$PF_TIME_US" "$hr" 0 "" >> $out
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
    outdir=$DATADIR/$PLOTID/
    mkdir -p $outdir
    for krate in 30000 100000 500000; do 
        plotname=${outdir}/xput_up_kr${krate}.${PLOTEXT}
        if [[ $FORCE ]] || [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            if [[ $FORCE ]]; then   #generate data
                for mode in "mod" "sim"; do 
                    gcc simulate.c -lpthread -o simulate $DEBUG_FLAG
                    for cores in 2 4 6 8; do
                        out=$outdir/xput_${mode}_${cores}_${krate}
                        echo "cores,hitratio,hitcost,pfcost,xput,faults" > $out
                        for hr in $(seq 0.5 0.1 1); do
                            if [ "$mode" == "mod" ]; then 
                                python model.py -c $cores -h1 $hr -th $HIT_TIME_NS \
                                    -tf $PF_TIME_US -kr $krate -u -tu $UPTIME_NS >> $out
                            else
                                ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                    "$PF_TIME_US" "$hr" 1 "$UPTIME_NS" | tee -a $out
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
    outdir=$DATADIR/$PLOTID/
    mkdir -p $outdir
    for krate in 500000; do 
        plotname=${outdir}/xput_noup_kr${krate}.${PLOTEXT}
        if [[ $FORCE ]] || [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
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
    outdir=$DATADIR/$PLOTID/
    mkdir -p $outdir
    montagename=${outdir}/xput_up_noup.${PLOTEXT}
    for krate in 500000; do 
        plotname=${outdir}/xput_up_noup_kr${krate}.${PLOTEXT}
        if [[ $FORCE ]] || [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            if [[ $FORCE ]]; then   #generate data
                for mode in "up" "noup"; do 
                    gcc simulate.c -lpthread -o simulate $DEBUG_FLAG
                    for cores in 2 4 6 8; do
                        out=$outdir/xput_${mode}_${cores}_${krate}
                        echo "cores,hitratio,hitcost,pfcost,xput,faults" > $out
                        for hr in $(seq 0.5 0.1 1); do
                            if [ "$mode" == "noup" ]; then 
                                ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                    "$PF_TIME_US" "$hr" 0 "" | tee -a $out
                            else
                                ./simulate $cores "$krate" "$HIT_TIME_NS" \
                                    "$PF_TIME_US" "$hr" 1 "$UPTIME_NS" | tee -a $out
                            fi
                        done
                    done
                done
            fi
            python3 ${SCRIPT_DIR}/../scripts/plot.py    \
                -xc hitratio -xl "Local Hit Ratio" -yc xput -yl "MOPS" --ymul 1e-6  \
                -d ${outdir}/xput_up_2_${krate}    -l "2"   -ls solid   -cmi 0      \
                -d ${outdir}/xput_noup_2_${krate}    -l ""    -ls dashed  -cmi 1    \
                -d ${outdir}/xput_up_4_${krate}    -l "4"   -ls solid   -cmi 0      \
                -d ${outdir}/xput_noup_4_${krate}    -l ""    -ls dashed  -cmi 1    \
                -d ${outdir}/xput_up_6_${krate}    -l "6"   -ls solid   -cmi 0      \
                -d ${outdir}/xput_noup_6_${krate}    -l ""    -ls dashed  -cmi 1    \
                -d ${outdir}/xput_up_8_${krate}    -l "8"   -ls solid   -cmi 0      \
                -d ${outdir}/xput_noup_8_${krate}    -l ""    -ls dashed  -cmi 1    \
                -lt "App CPU" -t "Kona $((krate/1000))k"                          \
                --size 4.5 3 -fs 11 -of $PLOTEXT -o $plotname 
        fi
        files="$files $plotname"
    done
    montage -tile 0x1 -geometry +5+5 -border 5 $files ${montagename}
    display $montagename &
fi