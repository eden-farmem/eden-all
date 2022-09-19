#!/bin/bash
set -e

#
# Benchmarking Fastswap's page fault bandwidth
# in various configurations
# 

usage="\n
-f, --force \t\t force re-run experiments\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
TEMP_PFX=tmp_kona_
PLOTSRC=${SCRIPT_DIR}/../../../scripts/plot.py
PLOTDIR=plots 
DATADIR=data
PLOTEXT=png

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -f|--force)
    FORCE=1
    ;;

    -h | --help)
    echo -e $usage
    exit
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# run
set +e    #to continue to cleanup even on failure
mkdir -p $DATADIR
CFLAGS_BEFORE=$CFLAGS

# for kind in "faults" "appfaults" "mixed"; do
for kind in "faults" "appfaults"; do
    for op in "read" "write"; do        # "r+w"
        cfg=${kind}-${op}
        KC=CONFIG_WP
        KO="-DNO_ZEROPAGE_OPT"  #to estimate normal faults after first access
        CFLAGS=${CFLAGS_BEFORE}
        LS=
        CMI=

        case $kind in
        "faults")           ;;
        "appfaults")        CFLAGS="$CFLAGS -DUSE_APP_FAULTS";;
        "mixed")            CFLAGS="$CFLAGS -DUSE_APP_FAULTS -DMIX_FAULTS";;
        *)                  echo "Unknown fault kind"; exit;;
        esac

        case $op in
        "read")             CFLAGS="$CFLAGS -DFAULT_OP=0";  LS=solid;   CMI=0;;
        "write")            CFLAGS="$CFLAGS -DFAULT_OP=1";  LS=dashed;  CMI=0;;
        "r+w")              CFLAGS="$CFLAGS -DFAULT_OP=2";  LS=dashdot; CMI=1;;
        *)                  echo "Unknown fault op"; exit;;
        esac

        datafile=$DATADIR/${cfg}
        if [ ! -f $datafile ] || [[ $FORCE ]]; then 
            bash run.sh -f -kc="$KC" -ko="$KO"  #rebuild kona
            tmpfile=${TEMP_PFX}out
            echo "cores,xput,latency" > $datafile
            for thr in `seq 1 1 6`; do 
                # bash run.sh -t=${thr} 
                bash run.sh -t=${thr} -fl="""$CFLAGS""" -o=${tmpfile}
            done
            grep "result:" $tmpfile | sed 's/result://' >> $datafile
            rm -f $tmpfile
        fi
        cat $datafile
        plots="$plots -d $datafile -l $cfg -ls $LS"

        # gather latency numbers
        latfile=${TEMP_PFX}latency-${op}
        if [ ! -f $latfile ]; then 
            echo "config,latency" > $latfile; 
            latplots="$latplots -d $latfile -l $op"
        fi
        row2col3=`sed -n '2p' ${datafile} | awk -F, '{ print $3 }'`
        echo "$kind,$row2col3" >> $latfile
    done
done

mkdir -p ${PLOTDIR}

plotname=fault_xput.${PLOTEXT}
python3 ${PLOTSRC} ${plots}             \
    -xc cores -xl "Cores"               \
    -yc xput -yl "Million faults / sec" \
    --ymul 1e-6 --ymin 0 --ymax 0.2     \
    --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname 
display $plotname & 

plotname=fault_latency.${PLOTEXT}
python3 ${PLOTSRC} -z bar ${latplots}   \
    -xc config -xl "Fault Type"         \
    -yc latency -yl "Cost (µs)"         \
    --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname 
display $plotname & 

plotname=fault_latency_zoomed.${PLOTEXT}
python3 ${PLOTSRC} -z bar ${latplots}   \
    -xc config -xl "Fault Type"         \
    -yc latency -yl "Cost (µs)"         \
    --ymin 13 --ymax 19 --hlines 14 15 16 17 18 \
    --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname
display $plotname & 

# cleanup
rm -f ${TEMP_PFX}*
