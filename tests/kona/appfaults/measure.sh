#!/bin/bash
set -e

#
# Benchmarking Kona's page fault bandwidth
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
latfile=$DATADIR/latency
echo "config,latency" > $latfile

for kind in "faults" "appfaults"; do
    for newpage in "zp" "no-zp"; do
        cfg=${kind}-${newpage}
        KC=CONFIG_WP
        KO=
        LINESTYLE=dashed
        CFLAGS=
        if [[ "$kind" == "appfaults" ]]; then  
            CFLAGS="$CFLAGS -DUSE_APP_FAULTS";
            LINESTYLE=solid
        fi
        if [[ "$newpage" == "zp" ]]; then  
            KO="-DNO_ZEROPAGE_OPT"; 
        fi

        datafile=$DATADIR/${cfg}
        if [ ! -f $datafile ] || [[ $FORCE ]]; then 
            bash run.sh --clean     #start clean
            bash run.sh -f -kc="$KC" -ko="$KO"  #rebuild kona
            tmpfile=${TEMP_PFX}out
            echo "cores,xput,latency" > $datafile
            for thr in `seq 1 1 5`; do 
                # bash run.sh -t=${thr} 
                bash run.sh -t=${thr} -fl="""$CFLAGS""" -o=${tmpfile}
            done
            grep "result:" $tmpfile | sed 's/result://' >> $datafile
            rm -f $tmpfile
        fi
        cat $datafile
        row2col3=`sed -n '2p' ${datafile} | awk -F, '{ print $3 }'`
        echo "$cfg,$row2col3" >> $latfile
        plots="$plots -d $datafile -l $cfg -ls $LINESTYLE"
    done
done

mkdir -p ${PLOTDIR}

plotname=fault_xput.${PLOTEXT}
python3 ${PLOTSRC} ${plots}             \
    -xc cores -xl "Cores"               \
    -yc xput -yl "Million faults / sec" --ymul 1e-6   \
    --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname
display $plotname & 

plotname=fault_latency.${PLOTEXT}
python3 ${PLOTSRC} -z bar -d ${latfile} \
    -xc config -xl "Type" --xstr        \
    -yc latency -yl "Cost (µs)" -l ""   \
    --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname
display $plotname & 

# cleanup
rm -f ${TEMP_PFX}*
