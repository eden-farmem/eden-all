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
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=plots 
DATADIR=data
PLOTEXT=png
CFGFILE=${TEMP_PFX}shenango.config
LATFILE=latencies
LATCORES=3

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
    
    -l|--lat)
    LATENCIES=1
    CFLAGS="$CFLAGS -DLATENCY"
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
cores=1

for kind in "regular" "apf-sync" "apf-async"; do    # "vanilla" 
# for kind in "apf-sync" "apf-async"; do    #
    for op in "random"; do        # "write" "read" "r+w" "random"
        # reset
        cfg=${kind}-${op}
        CFLAGS=${CFLAGS_BEFORE}
        OPTS=
        LS=
        CMI=
        rm -f ${LATFILE}

        case $kind in
        "vanilla")          ;;
        "regular")          CFLAGS="$CFLAGS -DFAULT_KIND=0"; OPTS="$OPTS --with-kona";;
        "apf-sync")         CFLAGS="$CFLAGS -DFAULT_KIND=1"; OPTS="$OPTS --with-kona --pgfaults=SYNC";;
        "apf-async")        CFLAGS="$CFLAGS -DFAULT_KIND=1"; OPTS="$OPTS --with-kona --pgfaults=ASYNC";;
        *)                  echo "Unknown fault kind"; exit;;
        esac

        case $op in
        "read")             CFLAGS="$CFLAGS -DFAULT_OP=0";  LS=solid;   CMI=0;;
        "write")            CFLAGS="$CFLAGS -DFAULT_OP=1";  LS=dashed;  CMI=0;;
        "r+w")              CFLAGS="$CFLAGS -DFAULT_OP=2";  LS=dashdot; CMI=1;;
        "random")           CFLAGS="$CFLAGS -DFAULT_OP=3";  LS=dotted;  CMI=1;;
        *)                  echo "Unknown fault op"; exit;;
        esac

        # run and log result
        datafile=$DATADIR/${cfg}
        if [ ! -f $datafile ] || [[ $FORCE ]]; then 
            bash run.sh ${OPTS} -fl="""$CFLAGS""" --force --buildonly   #recompile
            tmpfile=${TEMP_PFX}out
            echo "cores,xput" > $datafile
            for cores in `seq 1 1 10`; do 
                bash run.sh ${OPTS} -t=${cores} -fl="""$CFLAGS""" -o=${tmpfile}
                xput=$(grep "result:" $tmpfile | sed -n "s/^.*result://p")
                rm -f $tmpfile
                echo "$cores,$xput" >> $datafile        # record xput
                latfile=$DATADIR/lat-${cfg}-${cores}
                if [[ $LATENCIES ]] && [ -f $LATFILE ]; then 
                    mv -f ${LATFILE} ${latfile}            # record latency
                fi
            done
        fi
        cat $datafile
        plots="$plots -d $datafile -l $kind"
        latplots="$latplots -d $DATADIR/lat-${cfg}-${LATCORES} -l $kind"
    done
done

mkdir -p ${PLOTDIR}

plotname=${PLOTDIR}/fault_xput.${PLOTEXT}
python ${PLOTSRC} ${plots}                  \
    -xc cores -xl "App CPU"                 \
    -yc xput -yl "MOPS" --ymul 1e-6         \
    --ymin 0 --ymax .25                     \
    --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname 
display $plotname & 

if [[ $LATENCIES ]]; then 
    plotname=${PLOTDIR}/latency-${LATCORES}cores.${PLOTEXT}
    python3 ${PLOTSRC} -z cdf ${latplots}   \
        -yc latency -xl "Latency (µs)"      \
        --xmin 0 --xmax 200 -nm            \
        --size 5 3 -fs 11 -of ${PLOTEXT} -o $plotname 
    display $plotname & 
fi

# cleanup
rm -f ${TEMP_PFX}*
