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

for cfg in "faults-zp" "faults-no-zp"; do   #"app-faults-zp" "app-faults-no-zp"

    case $cfg in
    "faults-zp")        KC=CONFIG_WP;;
    "faults-no-zp")     KC=CONFIG_WP; KO="-DNO_ZEROPAGE_OPT";;
    *)                  echo "Unknown config"; exit;;
    esac

    datafile=$DATADIR/${cfg}
    if [ ! -f $datafile ] || [[ $FORCE ]]; then 
        bash run.sh --clean                 #start clean
        bash run.sh -f -kc="$KC" -ko="$KO"  #rebuild kona
        tmpfile=${TEMP_PFX}out
        echo "cores,xput" > $datafile
        for thr in `seq 1 1 5`; do 
            # bash run.sh -t=${thr} 
            bash run.sh -t=${thr} -o=${tmpfile}
        done
        grep "result:" $tmpfile | sed 's/result://' >> $datafile
        rm -f $tmpfile
    fi
    cat $datafile
    plots="$plots -d $datafile -l $cfg"
done

mkdir -p ${PLOTDIR}
plotname=fault_xput.${PLOTEXT}
python ${PLOTSRC} ${plots}          \
    -xc cores -xl "Cores"           \
    -yc xput -yl "Million faults / sec" --ymul 1e-6   \
    --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname
display $plotname & 

# cleanup
rm -f ${TEMP_PFX}*
