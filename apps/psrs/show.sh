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
-nk, --nkeys \t\t results filter: == nkeys\n
-lm, --lmem \t\t results filter: == localmem\n
-sc, --sched \t results filter: == scheduler\n
-be, --backend \t results filter: == backend\n
-pf, --pgfaults \t results filter: == pgfaults\n
-d, --desc \t\t results filter: contains desc\n
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

source ${ROOT_SCRIPTS_DIR}/utils.sh

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

    -nk=*|--nkeys=*)
    NKEYS="${i#*=}"
    ;;

    -lm=*|--lmem=*)
    LOCALMEM="${i#*=}"
    ;;

    -sc=*|--scheduler=*)
    SCHEDULER="${i#*=}"
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
    cores=$(cat $exp/settings | grep "cores:" | awk -F: '{ print $2 }')
    threads=$(cat $exp/settings | grep "threads:" | awk -F: '{ print $2 }')
    localmem=$(cat $exp/settings | grep "localmem:" | awk -F: '{ printf $2/1000000 }')
    pgfaults=$(cat $exp/settings | grep "pgfaults:" | awk -F: '{ print $2 }')
    sched=$(cat $exp/settings | grep "scheduler:" | awk -F: '{ print $2 }')
    backend=$(cat $exp/settings | grep "backend:" | awk -F: '{ print $2 }')
    nkeys=$(cat $exp/settings | grep "keys:" | awk -F: '{ print $2 }')
    desc=$(cat $exp/settings | grep "desc:" | awk -F: '{ print $2 }')
    sched=${sched:-none}
    backend=${backend:-none}
    pgfaults=${pgfaults:-none}

    # apply filters
    if [[ $THREADS ]] && [ "$THREADS" != "$threads" ];      then    continue;   fi
    if [[ $CORES ]] && [ "$CORES" != "$cores" ];            then    continue;   fi
    if [[ $NKEYS ]] && [ "$NKEYS" != "$nkeys" ];            then    continue;   fi
    if [[ $LOCALMEM ]] && [ "$LOCALMEM" != "$localmem" ];   then    continue;   fi
    if [[ $SCHEDULER ]] && [ "$SCHEDULER" != "$sched" ];    then    continue;   fi
    if [[ $BACKEND ]] && [ "$BACKEND" != "$backend" ];      then    continue;   fi
    if [[ $PGFAULTS ]] && [ "$PGFAULTS" != "$pgfaults" ];   then    continue;   fi
    # if [[ $DESC ]] && [[ "$desc" != *"$DESC"*  ]];        then    continue;   fi
    if [[ $DESC ]] && [[ "$desc" != "$DESC"  ]];            then    continue;   fi
    
    # overall performance

    # time breakdown
    if [ -f ${exp}/start ] && [ -f ${exp}/end ]; then 
        start=`cat ${exp}/start`
        rtime=$((`cat ${exp}/end`-`cat ${exp}/phase1`))
        p1time=$((`cat ${exp}/phase2`-`cat ${exp}/phase1`))
        p2time=$((`cat ${exp}/phase3`-`cat ${exp}/phase2`))
        p3time=$((`cat ${exp}/phase4`-`cat ${exp}/phase3`))
        p4time=$((`cat ${exp}/end`-`cat ${exp}/phase4`))
        # copyback=$((`cat ${exp}/end`-`cat ${exp}/copyback`))
    else
        rtime=$(cat ${exp}/app.out 2>/dev/null | grep -Eo "took: [0-9]+ ms \(microseconds\)" ${exp}/app.out | awk '{ print $2 }')
        p1time=$(cat ${exp}/app.out 2>/dev/null | grep -Eo "phase 1 took [0-9]+ ms" | awk '{ print $4 }')
        p2time=$(cat ${exp}/app.out 2>/dev/null | grep -Eo "phase 2 took [0-9]+ ms" | awk '{ print $4 }')
        p3time=$(cat ${exp}/app.out 2>/dev/null | grep -Eo "phase 3 took [0-9]+ ms" | awk '{ print $4 }')
        p4time=$(cat ${exp}/app.out 2>/dev/null | grep -Eo "phase 4 took [0-9]+ ms" | awk '{ print $4 }')
    fi
    unaccounted=
    cpuwork=
    if [[ $rtime ]]; then 
        cpuwork=$((rtime*cores))
        unaccounted=$((rtime-p1time-p2time-p3time-p4time))
    fi

    # kona numbers
    konastatsout=${exp}/kona_counters_parsed
    konastatsin=${exp}/kona_counters.out 
    if [ ! -f $konastatsout ] && [ -f $konastatsin ]; then 
        python ${ROOT_SCRIPTS_DIR}/parse_kona_counters.py -i ${konastatsin} -o ${konastatsout}
    fi
    faultsr=$(csv_column_mean "$konastatsout" "n_faults_r")
    faultsw=$(csv_column_mean "$konastatsout" "n_faults_w")
    faultswp=$(csv_column_mean "$konastatsout" "n_faults_wp")
    afaultsr=$(csv_column_mean "$konastatsout" "n_afaults_r")
    faults=$((faultsr+faultsw+faultswp))

    # write
    HEADER="Exp";                   LINE="$name";
    HEADER="$HEADER,Scheduler";     LINE="$LINE,${sched}";
    HEADER="$HEADER,Backend";       LINE="$LINE,${backend}";
    # HEADER="$HEADER,PFType";        LINE="$LINE,${pgfaults}";
    HEADER="$HEADER,CPU";           LINE="$LINE,${cores}";
    HEADER="$HEADER,Threads";       LINE="$LINE,${threads}";
    HEADER="$HEADER,Keys";          LINE="$LINE,$((nkeys/1000000))M";
    HEADER="$HEADER,Time(s)";       LINE="$LINE,$((rtime))";
    HEADER="$HEADER,Work";          LINE="$LINE,${cpuwork}";
    HEADER="$HEADER,Phase1";        LINE="$LINE,$((p1time))"; #$(percentof "$p1time" "$rtime")
    HEADER="$HEADER,Phase2";        LINE="$LINE,$((p2time))";
    HEADER="$HEADER,Phase3";        LINE="$LINE,$((p3time))";
    HEADER="$HEADER,Phase4";        LINE="$LINE,$((p4time))";
    HEADER="$HEADER,Unacc";         LINE="$LINE,$((unaccounted))"; 

    HEADER="$HEADER,Local_MB";      LINE="$LINE,${localmem}";
    # HEADER="$HEADER,Faults";        LINE="$LINE,${faults}";
    # HEADER="$HEADER,ReadPF";        LINE="$LINE,${faultsr}";
    # HEADER="$HEADER,ReadAPF";       LINE="$LINE,${afaultsr}";
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