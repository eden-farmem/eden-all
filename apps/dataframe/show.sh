#!/bin/bash
# set -e
#
# Show info on past (good) runs
#

usage="\n
-s, --suffix \t\t a plain suffix defining the set of runs to show\n
-cs, --csuffix \t same as suffix but a more complex one (with regexp pattern)\n
-c, --cores \t\t results filter: == cores\n
-lm, --lmem \t\t results filter: == localmem\n
-lmp, --lmemp \t\t results filter: == localmem%\n
-be, --backend \t results filter: == backend\n
-pf, --pgfaults \t results filter: == pgfaults\n
-d, --desc \t\t results filter: contains desc\n
-tg, --tag \t\t results filter: == tag\n
-f, --force \t\t remove any cached data and parse from scratch\n
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

    -i=*|--input=*)
    INPUT="${i#*=}"
    ;;

    -lm=*|--lmem=*)
    LOCALMEM="${i#*=}"
    ;;

    -lmp=*|--lmemp=*)
    LOCALMEMPER="${i#*=}"
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

    -d=*|--desc=*)
    DESC="${i#*=}"
    ;;

    -tg=*|--tag=*)
    TAG="${i#*=}"
    ;;

    -f|--force)
    FORCE=1
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
    input=$(cat $exp/settings | grep "input:" | awk -F: '{ printf $2 }')
    localmem=$(cat $exp/settings | grep "localmem:" | awk -F: '{ printf $2/1000000 }')
    localmemp=$(cat $exp/settings | grep "localmempercent:" | awk -F: '{ printf $2 }')
    pgfaults=$(cat $exp/settings | grep "pgfaults:" | awk -F: '{ print $2 }')
    sched=$(cat $exp/settings | grep "scheduler:" | awk -F: '{ print $2 }')
    backend=$(cat $exp/settings | grep "backend:" | awk -F: '{ print $2 }')
    nkeys=$(cat $exp/settings | grep "keys:" | awk -F: '{ print $2 }')
    desc=$(cat $exp/settings | grep "desc:" | awk -F: '{ print $2 }')
    tag=$(cat $exp/settings | grep "tag:" | awk -F: '{ print $2 }')
    sched=${sched:-none}
    backend=${backend:-none}
    pgfaults=${pgfaults:-none}
    tag=${tag:-none}

    # apply filters
    if [[ $THREADS ]] && [ "$THREADS" != "$threads" ];              then    continue;   fi
    if [[ $CORES ]] && [ "$CORES" != "$cores" ];                    then    continue;   fi
    if [[ $APP ]] && [ "$APP" != "$app" ];                          then    continue;   fi
    if [[ $INPUT ]] && [ "$INPUT" != "$input" ];                    then    continue;   fi
    if [[ $LOCALMEM ]] && [ "$LOCALMEM" != "$localmem" ];           then    continue;   fi
    if [[ $LOCALMEMPER ]] && [ "$LOCALMEMPER" != "$localmemp" ];    then    continue;   fi
    if [[ $SCHEDULER ]] && [ "$SCHEDULER" != "$sched" ];            then    continue;   fi
    if [[ $BACKEND ]] && [ "$BACKEND" != "$backend" ];              then    continue;   fi
    if [[ $PGFAULTS ]] && [ "$PGFAULTS" != "$pgfaults" ];           then    continue;   fi
    if [[ $DESC ]] && [[ "$desc" != "$DESC"  ]];                    then    continue;   fi
    if [[ $TAG ]] && [[ "$tag" != "$TAG"  ]];                       then    continue;   fi
    
    ## PERFORMANCE BREAKDOWN
    rtime=$(cat ${exp}/app.out | grep -a "Total:" | awk '{ print $2 }')

    # KONA
    konastatsout=${exp}/kona_counters_parsed
    konastatsin=${exp}/kona_counters.out 
    if ([[ $FORCE ]] || [ ! -f $konastatsout ]) && [ -f $konastatsin ]; then 
        python ${ROOT_SCRIPTS_DIR}/parse_kona_counters.py -i ${konastatsin} -o ${konastatsout}
    fi
    faultsr=$(csv_column_sum "$konastatsout" "n_faults_r")
    faultsw=$(csv_column_sum "$konastatsout" "n_faults_w")
    faultswp=$(csv_column_sum "$konastatsout" "n_faults_wp")
    mallocd=$(csv_column_max "$konastatsout" "malloc_size" | ftoi)
    maxrss=$(csv_column_max "$konastatsout" "mem_pressure" | ftoi)
    madvsize=$(csv_column_max "$konastatsout" "madvise_size" | ftoi)

    # SETTINGS
    HEADER="Exp";                   LINE="$name";
    # HEADER="$HEADER,Scheduler";     LINE="$LINE,${sched}";
    HEADER="$HEADER,Backend";       LINE="$LINE,${backend}";
    # HEADER="$HEADER,PFType";        LINE="$LINE,${pgfaults}";
    # HEADER="$HEADER,Input";         LINE="$LINE,${input}";
    # HEADER="$HEADER,Tag";           LINE="$LINE,${tag}";
    HEADER="$HEADER,CPU";           LINE="$LINE,${cores}";
    HEADER="$HEADER,Thr";           LINE="$LINE,${threads}";
    HEADER="$HEADER,LocalMem(MB)";  LINE="$LINE,${localmem}";
    HEADER="$HEADER,LocalMem(%)";   LINE="$LINE,${localmemp:-}";
    HEADER="$HEADER,Time(s)";       LINE="$LINE,$((rtime/1000000))";
    HEADER="$HEADER,FaultsR";       LINE="$LINE,${faultsr}";
    HEADER="$HEADER,FaultsW";       LINE="$LINE,${faultsw}";
    HEADER="$HEADER,FaultsWP";      LINE="$LINE,${faultswp}";
    HEADER="$HEADER,Mallocd";       LINE="$LINE,$((mallocd/1000000))";
    HEADER="$HEADER,MaxRSS";        LINE="$LINE,$((maxrss/1000000))";
    HEADER="$HEADER,MAdvise";        LINE="$LINE,$((madvsize/1000000))";
    # HEADER="$HEADER,Desc";          LINE="$LINE,${desc:0:30}";
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