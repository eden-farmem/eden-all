#!/bin/bash
# set -e
#
# Show info on past (good) runs
#

usage="\n
-s, --suffix \t\t a plain suffix defining the set of runs to show\n
-cs, --csuffix \t same as suffix but a more complex one (with regexp pattern)\n
-t, --threads \t\t results filter: == threads\n
-c, --cores \t\t results filter: == cores\n
-d, --desc \t\t results filter: contains desc\n
-lm, --lmem \t\t results filter: == localmem\n
-be, --backend \t results filter: == backend\n
-pf, --pgfaults \t results filter: == pgfaults\n
-zs, --zipfs \t\t results filter: == zipfs\n
-rm, --remove \t\t (recoverably) delete runs that match these filters\n
-of, --outfile \t output results to a file instead of stdout\n"

SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
DATADIR="${SCRIPT_DIR}/data"
ROOT_DIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOT_DIR}/scripts/"
HOST="sc2-hs2-b1630"
CLIENT="sc2-hs2-b1632"
TRASH="${DATADIR}/trash"

source ${SCRIPT_DIR}/shared.sh

# Read parameters
for i in "$@"
do
case $i in
    -s=*|--suffix=*)
    SUFFIX="${i#*=}"
    ;;

    -cs=*|--csuffix=*)
    CSUFFIX="${i#*=}"
    ;;
    
    -of=*|--outfile=*)
    OUTFILE="${i#*=}"
    ;;

    -rm|--remove)
    DELETE=1
    ;;

    # OUTPUT FILTERS
    -c=*|--cores=*)
    CORES="${i#*=}"
    ;;

    -t=*|--threads=*)
    THREADS="${i#*=}"
    ;;

    -lm=*|--lmem=*)
    LOCALMEM="${i#*=}"
    ;;

    -be=*|--backend=*)
    BACKEND="${i#*=}"
    ;;

    -pf=*|--pgfaults=*)
    PGFAULTS="${i#*=}"
    ;;

    -zs=*|--zipfs=*)
    ZIPFS="${i#*=}"
    ;;

    -d=*|--desc=*)
    DESC="${i#*=}"
    ;;

    -*|--*)     # unknown option
    echo "Unknown Option: $i"
    echo -e $usage
    exit
    ;;

    *)          # take any other option as simple suffix     
    SUFFIX="${i}"
    ;;

esac
done

if [[ $SUFFIX ]]; then 
    LS_CMD=`ls -d1 ${DATADIR}/run-${SUFFIX}*/`
    SUFFIX=$SUFFIX
elif [[ $CSUFFIX ]]; then
    LS_CMD=`ls -d1 ${DATADIR}/*/ | grep -e "$CSUFFIX"`
    SUFFIX=$CSUFFIX
else 
    SUFFIX=$(date +"%m-%d")     # default to today
    LS_CMD=`ls -d1 data/run-${SUFFIX}*/`
fi
# echo $LS_CMD

for exp in $LS_CMD; do
    # echo $exp
    name=$(basename $exp)
    cores=$(cat $exp/settings | grep "cores" | awk -F: '{ print $2 }')
    threads=$(cat $exp/settings | grep "threads" | awk -F: '{ print $2 }')
    localmem=$(cat $exp/settings | grep "localmem" | awk -F: '{ printf $2/1000000 }')
    pgfaults=$(cat $exp/settings | grep "pgfaults" | awk -F: '{ print $2 }')
    backend=$(cat $exp/settings | grep "backend" | awk -F: '{ print $2 }')
    nkeys=$(cat $exp/settings | grep "keys" | awk -F: '{ print $2 }')
    nblobs=$(cat $exp/settings | grep "blobs" | awk -F: '{ print $2 }')
    zipfs=$(cat $exp/settings | grep "zipfs" | awk -F: '{ print $2 }')
    desc=$(cat $exp/settings | grep "desc" | awk -F: '{ print $2 }')
    backend=${backend:-none}
    pgfaults=${pgfaults:-none}

    # apply filters
    if [[ $THREADS ]] && [ "$THREADS" != "$threads" ];  then    continue;   fi
    if [[ $CORES ]] && [ "$CORES" != "$cores" ];        then    continue;   fi
    if [[ $LOCALMEM ]] && [ "$LOCALMEM" != "$localmem" ]; then  continue;   fi
    if [[ $BACKEND ]] && [ "$BACKEND" != "$backend" ];  then    continue;   fi
    if [[ $PGFAULTS ]] && [ "$PGFAULTS" != "$pgfaults" ]; then  continue;   fi
    if [[ $ZIPFS ]] && [ "$ZIPFS" != "$zipfs" ];        then    continue;   fi
    # if [[ $DESC ]] && [[ "$desc" != *"$DESC"*  ]];      then    continue;   fi
    if [[ $DESC ]] && [[ "$desc" != "$DESC"  ]];      then    continue;   fi
    
    # gather numbers
    preload_start=$(cat $exp/preload_start 2>/dev/null)
    preload_end=$(cat $exp/preload_end 2>/dev/null)
    ptime=$((preload_end-preload_start))

    rstart=$(cat $exp/run_start 2>/dev/null)
    rend=$(cat $exp/run_end 2>/dev/null)
    rtime=$((rend-rstart))
    xput=$(grep "result:" $exp/app.out | sed -n "s/^.*result://p")
    xputpercore=
    if [[ $xput ]]; then xputpercore=$((xput/cores));   fi

    konastatsout=${exp}/kona_counters_parsed
    konastatsin=${exp}/kona_counters.out 
    if [ ! -f $konastatsout ] && [ -f $konastatsin ] && [[ $rstart ]] && [[ $rend ]]; then 
        python ${ROOT_SCRIPTS_DIR}/parse_kona_counters.py -i ${konastatsin} \
            -st=${rstart} -et ${rend} -o ${konastatsout}
    fi
    faultsr=$(csv_column_mean "$konastatsout" "n_faults_r")
    faultsw=$(csv_column_mean "$konastatsout" "n_faults_w")
    faultswp=$(csv_column_mean "$konastatsout" "n_faults_wp")
    afaultsr=$(csv_column_mean "$konastatsout" "n_afaults_r")
    faults=$((faultsr+faultsw+faultswp))

    # write
    HEADER="Exp";                   LINE="$name";
    HEADER="$HEADER,Backend";       LINE="$LINE,${backend}";
    HEADER="$HEADER,PFType";        LINE="$LINE,${pgfaults}";
    HEADER="$HEADER,CPU";           LINE="$LINE,${cores}";
    HEADER="$HEADER,Threads";       LINE="$LINE,${threads}";
    HEADER="$HEADER,Local_MB";      LINE="$LINE,${localmem}";
    HEADER="$HEADER,ZipfS";         LINE="$LINE,${zipfs}";
    # HEADER="$HEADER,PreloadTime";   LINE="$LINE,${ptime}";
    HEADER="$HEADER,Runtime";       LINE="$LINE,${rtime}";
    HEADER="$HEADER,Xput";          LINE="$LINE,${xput:-}";
    HEADER="$HEADER,XputPerCore";   LINE="$LINE,${xputpercore}";
    HEADER="$HEADER,Faults";        LINE="$LINE,${faults}";
    HEADER="$HEADER,ReadPF";        LINE="$LINE,${faultsr}";
    HEADER="$HEADER,ReadAPF";       LINE="$LINE,${afaultsr}";
    # HEADER="$HEADER,WritePF";       LINE="$LINE,${faultsw}";
    # HEADER="$HEADER,WPFaults";      LINE="$LINE,${faultswp}";
    HEADER="$HEADER,Desc";          LINE="$LINE,${desc:0:30}";    
    OUT=`echo -e "${OUT}\n${LINE}"`

    if [[ $DELETE ]]; then 
        mkdir -p ${TRASH}
        mv ${exp} ${TRASH}/
    fi
done

if [[ $OUTFILE ]]; then 
    echo "${HEADER}${OUT}" > $OUTFILE
    echo "wrote results to $OUTFILE"
else
    echo "${HEADER}${OUT}" | column -s, -t -n
fi

if [[ $DELETE ]]; then 
    echo "trashed these runs at ${TRASH}; clean it up if needed"
fi