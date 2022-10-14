#!/bin/bash
set -e
set +x

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

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="-DDEBUG $CFLAGS"
    ;;

    -f|--force)
    FORCE=1
    ;;
    
    -l|--lat)
    LATENCIES=1
    CFLAGS="-DLATENCY $CFLAGS"
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
NHANDLERS=4

for rmem in "rmem-evict"; do    # "none" "rmem" "hints"
    for op in "read"; do        # "write" "read" "r+w" "random"
        # reset
        cfg=${rmem}-${op}-${NHANDLERS}hthr
        CFLAGS=${CFLAGS_BEFORE}
        OPTS=
        LS=
        CMI=
        rm -f ${LATFILE}

        case $rmem in
        "none")             ;;
        "rmem")             OPTS="$OPTS --rmem";;
        "rmem-evict")       OPTS="$OPTS --rmem --evict";;
        "hints")            OPTS="$OPTS --rmem --hints";;
        "hints-evict")      OPTS="$OPTS --rmem --hints --evict";;
        *)                  echo "Unknown rmem type"; exit;;
        esac

        case $op in
        "read")             CFLAGS="-DFAULT_OP=0 $CFLAGS";  LS=solid;   CMI=0;;
        "write")            CFLAGS="-DFAULT_OP=1 $CFLAGS ";  LS=dashed;  CMI=0;;
        "r+w")              CFLAGS="-DFAULT_OP=2 $CFLAGS ";  LS=dashdot; CMI=1;;
        "random")           CFLAGS="-DFAULT_OP=3 $CFLAGS ";  LS=dotted;  CMI=1;;
        *)                  echo "Unknown fault op"; exit;;
        esac

        # run and log result
        datafile=$DATADIR/xput-${cfg}
        if [ ! -f $datafile ] || [[ $FORCE ]]; then 
            bash run.sh ${OPTS} -fl="""$CFLAGS""" --force --buildonly   #recompile
            tmpfile=${TEMP_PFX}out
            echo "cores,xput" > $datafile
            for cores in `seq 1 1 8`; do 
            # for cores in 1 4 8 12; do 
                rm -f result
                bash run.sh ${OPTS} -t=${cores} -fl="""$CFLAGS"""
                xput=$(cat result 2>/dev/null)
                rm -f $tmpfile
                echo "$cores,$xput" >> $datafile        # record xput
                latfile=$DATADIR/lat-${cfg}
                if [[ $LATENCIES ]] && [ -f $LATFILE ]; then 
                    mv -f ${LATFILE} ${latfile}            # record latency
                fi

                # clean and wait a bit
                bash run.sh --clean
                sleep 10
            done
        fi
        cat $datafile
        plots="$plots -d $datafile -l $rmem"
        latplots="$latplots -d $DATADIR/lat-${cfg} -l $rmem-$op-${NHANDLERS}hthr"
        wc -l $DATADIR/lat-${cfg}
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
