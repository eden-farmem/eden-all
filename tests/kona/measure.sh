#!/bin/bash
set -e

#
# Benchmarking Kona's page fault bandwidth
# in various configurations
# 

usage="\n
-f, --force \t\t force re-run experiments\n
-l, --lat \t\t get latencies\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
TEMP_PFX=tmp_kona_
PLOTSRC=${SCRIPT_DIR}/../../../scripts/plot.py
PLOTDIR=plots 
DATADIR=data
PLOTEXT=png
LATFILE=latencies

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -l|--lat)
    LATENCIES=1
    CFLAGS="$CFLAGS -DLATENCY"
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
# CFLAGS="$CFLAGS -DSAFE_MODE"
CFLAGS_BEFORE=$CFLAGS

# for kind in "faults" "appfaults" "mixed"; do
for kind in "faults"; do
    for op in "read"; do        # "r+w" "write"
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

        datafile=$DATADIR/xput-${cfg}
        if [ ! -f $datafile ] || [[ $FORCE ]]; then 
            bash run.sh -f -kc="$KC" -ko="$KO" --buildonly  #rebuild kona
            tmpfile=${TEMP_PFX}out
            echo "cores,xput" > $datafile
            for thr in `seq 1 1 1`; do 
                bash run.sh -t=${thr} -fl="""$CFLAGS""" -o=${tmpfile}
            done
            grep "result:" $tmpfile | sed 's/result://' >> $datafile
            rm -f $tmpfile
            cat $datafile
            latfile=$DATADIR/lat-${cfg}
            if [[ $LATENCIES ]] && [ -f $LATFILE ]; then 
                mv -f ${LATFILE} ${latfile}            # save latency
            fi
        fi
        cat $datafile
        plots="$plots -d $datafile -l $cfg -ls $LS"
        latplots="$latplots -d $latfile -l $cfg"

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

# plotname=${PLOTDIR}/fault_xput.${PLOTEXT}
# python3 ${PLOTSRC} ${plots}             \
#     -xc cores -xl "Cores"               \
#     -yc xput -yl "Million faults / sec" \
#     --ymul 1e-6 --ymin 0 --ymax 0.2     \
#     --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname 
# display $plotname & 

# if [[ $LATENCIES ]]; then 
#     echo $latplots
#     plotname=${PLOTDIR}/latency.${PLOTEXT}
#     python3 ${PLOTSRC} -z cdf ${latplots}   \
#         -yc latency -xl "Latency (µs)"      \
#         --xmin 10 --xmax 20 -nm             \
#         --size 8 3.5 -fs 12 -of ${PLOTEXT} -o $plotname 
#     display $plotname & 
# fi

# cleanup
rm -f ${TEMP_PFX}*
