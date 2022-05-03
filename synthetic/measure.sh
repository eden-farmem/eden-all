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
TEMP_PFX=tmp_msyn_
PLOTSRC=${SCRIPT_DIR}/../scripts/plot.py
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
thr=1       #not thread-safe yet
nkeys=1000000
nreqs=100000000
sample=1

for kind in "vanilla"; do    #
# for kind in "vanilla" "regular" "apf-sync" "apf-async"; do    #
    for op in "none" "zip" "enc"; do
        for sample in 1; do
            # reset
            cfg=${kind}-${op}-${cores}c-${thr}t-${nkeys}k-${sample}
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
            "none")                                                     LS=solid;   CMI=0;;
            "zip")              CFLAGS="$CFLAGS -DCOMPRESS";            LS=dashed;  CMI=0;;
            "enc")              CFLAGS="$CFLAGS -DENCRYPT";             LS=dashdot; CMI=1;;
            "enc+zip")          CFLAGS="$CFLAGS -DCOMPRESS -DENCRYPT";  LS=dotted;  CMI=1;;
            *)                  echo "Unknown op"; exit;;
            esac

            # run and log result
            datafile=$DATADIR/${cfg}
            if [ ! -f $datafile ] || [[ $FORCE ]]; then 
                bash run.sh ${OPTS} -fl="""$CFLAGS""" --force --buildonly   #recompile
                tmpfile=${TEMP_PFX}out
                echo "cores,thr,nkeys,zipfs,xput" > $datafile
                for s in `seq 1 3 10`; do 
                    zipfs=$(echo $s | awk '{ printf("%.1lf", $1/10.0); }')
                    echo $cores,$thr,$zipfs,$nkeys,$zipfs
                    bash run.sh ${OPTS} -t=${cores} -fl="""$CFLAGS""" -c=${cores} -t=${thr} \
                        -nk=${nkeys} -nr=${nreqs} -zs=${zipfs} -o=${tmpfile}
                    xput=$(grep "result:" $tmpfile | sed -n "s/^.*result://p")
                    rm -f $tmpfile
                    echo "$cores,$thr,$zipfs,$nkeys,$zipfs,$xput" >> $datafile  #record xput
                    latfile=$DATADIR/lat-${cfg}-${cores}
                    if [[ $LATENCIES ]] && [ -f $LATFILE ]; then 
                        mv -f ${LATFILE} ${latfile}            #record latency
                    fi
                done
            fi
            cat $datafile
            plots="$plots -d $datafile -l $op"
            latplots="$latplots -d $DATADIR/lat-${cfg}-${LATCORES} -l $op"
        done
    done
done

mkdir -p ${PLOTDIR}

plotname=${PLOTDIR}/xput-${cores}c-${thr}t-${nkeys}k.${PLOTEXT}
python ${PLOTSRC} ${plots}                  \
    -xc zipfs -xl "Zipf s-param"            \
    -yc xput -yl "Ops/sec" --ylog           \
    --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname 
display $plotname & 

# if [[ $LATENCIES ]]; then 
#     plotname=${PLOTDIR}/latency-${LATCORES}cores.${PLOTEXT}
#     python3 ${PLOTSRC} -z cdf ${latplots}   \
#         -yc latency -xl "Latency (µs)"      \
#         --xmin 0 --xmax 200 -nm            \
#         --size 5 3 -fs 11 -of ${PLOTEXT} -o $plotname 
#     display $plotname & 
# fi

# cleanup
rm -f ${TEMP_PFX}*
