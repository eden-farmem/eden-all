#!/bin/bash
# set -e
#
# Show info on past (good) runs
#

usage="\n
-s, --suffix \t\t a plain suffix defining the set of runs to show\n
-cs, --csuffix \t same as suffix but a more complex one (with regexp pattern)\n
-lm, --lmem \t\t results filter: == localmem\n
-lmp, --lmemp \t\t results filter: == localmem%\n
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
    -lm=*|--lmem=*)
    LOCALMEM="${i#*=}"
    ;;

    -lmp=*|--lmemp=*)
    LOCALMEMPER="${i#*=}"
    ;;

    -b=*|--benchmark=*)
    BENCHMARK="${i#*=}"
    ;;

    -o=*|--ops=*)
    OPS="${i#*=}"
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
    benchmark=$(cat $exp/settings | grep "benchmark:" | awk -F: '{ print $2 }')
    ops=$(cat $exp/settings | grep "ops:" | awk -F: '{ print $2 }')
    handlers=$(cat $exp/settings | grep "handlers:" | awk -F: '{ print $2 }')
    samples=$(cat $exp/settings | grep "samples:" | awk -F: '{ print $2 }')
    localmem=$(cat $exp/settings | grep "localmem:" | awk -F: '{ printf $2/1000000 }')
    localmemp=$(cat $exp/settings | grep "localmempercent:" | awk -F: '{ printf $2 }')
    desc=$(cat $exp/settings | grep "desc:" | awk -F: '{ print $2 }')

    # apply filters
    if [[ $BENCHMARK ]] && [[ "$benchmark" != "$BENCHMARK"  ]];     then    continue;   fi
    if [[ $OPS ]] && [[ "$ops" != "$OPS"  ]];                       then    continue;   fi
    if [[ $LOCALMEM ]] && [ "$LOCALMEM" != "$localmem" ];           then    continue;   fi
    if [[ $LOCALMEMPER ]] && [ "$LOCALMEMPER" != "$localmemp" ];    then    continue;   fi
    if [[ $DESC ]] && [[ "$desc" != "$DESC"  ]];                    then    continue;   fi
    if [[ $TAG ]] && [[ "$tag" != "$TAG"  ]];                       then    continue;   fi

    # TOOL OUTPUT
    fltraceout=${exp}/fltrace_parsed
    fltracein=${exp}/fault-stats.out
    if [ ! -f $fltraceout ] && [ -f $fltracein ]; then 
        python3 ${ROOT_SCRIPTS_DIR}/parse_fltrace_stat.py -i ${fltracein} -o ${fltraceout}
    fi
    faultsr=$(csv_column_mean "$fltraceout" "faults_r")
    faultsw=$(csv_column_mean "$fltraceout" "faults_w")
    faultswp=$(csv_column_mean "$fltraceout" "faults_wp")
    mallocd=$(csv_column_max "$fltraceout" "memory_allocd_mb" | ftoi)
    maxrss=$(csv_column_max "$fltraceout" "memory_used_mb" | ftoi)
    freed=$(csv_column_max "$fltraceout" "memory_freed_mb" | ftoi)
    vmsize=$(csv_column_max "$fltraceout" "vm_size_mb" | ftoi)
    vmrss=$(csv_column_max "$fltraceout" "vm_rss_mb" | ftoi)

    # SETTINGS
    HEADER="Exp";                   LINE="$name";
    HEADER="$HEADER,Bench";         LINE="$LINE,${benchmark}";
    HEADER="$HEADER,Ops";           LINE="$LINE,${ops}";
    HEADER="$HEADER,LocalMem(MB)";  LINE="$LINE,${localmem}";
    HEADER="$HEADER,LocalMem(%)";   LINE="$LINE,${localmemp:-}";
    HEADER="$HEADER,Time(s)";       LINE="$LINE,${rtime}";
    HEADER="$HEADER,FaultsR";       LINE="$LINE,${faultsr}";
    HEADER="$HEADER,FaultsW";       LINE="$LINE,${faultsw}";
    HEADER="$HEADER,FaultsWP";      LINE="$LINE,${faultswp}";
    HEADER="$HEADER,Mallocd";       LINE="$LINE,$((mallocd))";
    HEADER="$HEADER,Freed";         LINE="$LINE,$((freed))";
    HEADER="$HEADER,MaxRSS";        LINE="$LINE,$((maxrss))";
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
    echo "${HEADER}${OUT}" | column -s, -t
fi

if [[ $DELETE ]]; then 
    echo "trashed these runs at ${TRASH}; clean it up if needed"
fi