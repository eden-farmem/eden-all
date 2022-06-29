#!/bin/bash
# set -e
#
# Show info on past (good) runs
#

usage="\n
-s, --suffix \t\t a plain suffix defining the set of runs to show\n
-cs, --csuffix \t same as suffix but a more complex one (with regexp pattern)\n
-c, --cores \t\t results filter: == cores\n
-nk, --nkeys \t\t results filter: == nkeys\n
-lm, --lmem \t\t results filter: == localmem\n
-be, --backend \t results filter: == backend\n
-pf, --pgfaults \t results filter: == pgfaults\n
-d, --desc \t\t results filter: contains desc\n
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
    if [[ $DESC ]] && [[ "$desc" != "$DESC"  ]];            then    continue;   fi
    
    # overall performance

    # time breakdown
    if [ -f ${exp}/start ] && [ -f ${exp}/end ]; then 
        start=`cat ${exp}/start`
        rtime=$((`cat ${exp}/end`-`cat ${exp}/phase1`))
        p1time=$((`cat ${exp}/phase2`-`cat ${exp}/phase1`))
        p2time=$((`cat ${exp}/phase3`-`cat ${exp}/phase2`))
        p3time=$((`cat ${exp}/phase4`-`cat ${exp}/phase3`))
        p4time=$((`cat ${exp}/copyback`-`cat ${exp}/phase4`))
        copyback=$((`cat ${exp}/end`-`cat ${exp}/copyback`))
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
        unaccounted=$((rtime-p1time-p2time-p3time-p4time-copyback))
    fi

    sflag=
    eflag=
    # if [ -f ${exp}/phase1 ]; then   sflag="--start `cat ${exp}/phase1`";    fi
    if [ -f ${exp}/copyback ]; then   sflag="--start `cat ${exp}/copyback`";    fi
    if [ -f ${exp}/end ]; then      eflag="--end `cat ${exp}/end`";         fi

    # KONA
    konastatsout=${exp}/kona_counters_parsed
    konastatsin=${exp}/kona_counters.out 
    if [[ $FORCE ]] || ([ ! -f $konastatsout ] && [ -f $konastatsin ]); then 
        python ${ROOT_SCRIPTS_DIR}/parse_kona_counters.py -i ${konastatsin}     \
            -o ${konastatsout} ${sflag} ${eflag}
    fi
    faultsr=$(csv_column_sum "$konastatsout" "n_faults_r")
    faultsw=$(csv_column_sum "$konastatsout" "n_faults_w")
    faultswp=$(csv_column_sum "$konastatsout" "n_faults_wp")
    afaultsr=$(csv_column_sum "$konastatsout" "n_afaults_r")
    afaultsw=$(csv_column_sum "$konastatsout" "n_afaults_w")
    faults=$((faultsr+faultsw+faultswp))
    afaults=$((afaultsr+afaultsw))

    # SHENANGO
    shenangoout=${exp}/runtime_parsed
    shenangoin=${exp}/runtime.out 
    if [[ $FORCE ]] || ([ ! -f $shenangoout ] && [ -f $shenangoin ]); then 
        python ${ROOT_SCRIPTS_DIR}/parse_shenango_runtime.py -i ${shenangoin}   \
            -o ${shenangoout} ${sflag} ${eflag}
    fi
    schedtimepct=$(csv_column_mean "$shenangoout" "schedtimepct")
    pf_posted=$(csv_column_sum "$shenangoout" "pf_posted")
    pf_returned=$(csv_column_sum "$shenangoout" "pf_returned")
    pf_time_total_mus=$(csv_column_sum "$shenangoout" "pf_time_spent_mus")
    pf_time_each_mus=$(echo $pf_time_total_mus $pf_posted | awk '{ if ($2 != 0) print $1/$2 }')

    # WRITE
    HEADER=;                        LINE=;
    HEADER="$HEADER,Exp";           LINE="$LINE,$name";
    # HEADER="$HEADER,Scheduler";     LINE="$LINE,${sched}";
    HEADER="$HEADER,Backend";       LINE="$LINE,${backend}";
    HEADER="$HEADER,PFType";        LINE="$LINE,${pgfaults}";
    HEADER="$HEADER,Keys";          LINE="$LINE,$((nkeys/1000000))M";
    HEADER="$HEADER,CPU";           LINE="$LINE,${cores}";
    HEADER="$HEADER,Thr";           LINE="$LINE,${threads}";
    HEADER="$HEADER,Time(s)";       LINE="$LINE,$((rtime))";
    # HEADER="$HEADER,Work";          LINE="$LINE,${cpuwork}";
    HEADER="$HEADER,Phase1";        LINE="$LINE,$((p1time))";
    HEADER="$HEADER,Phase2";        LINE="$LINE,$((p2time))";
    HEADER="$HEADER,Phase3";        LINE="$LINE,$((p3time))";
    HEADER="$HEADER,Phase4";        LINE="$LINE,$((p4time))";
    HEADER="$HEADER,Copyback";      LINE="$LINE,$((copyback))";
    # HEADER="$HEADER,Unacc";         LINE="$LINE,$((unaccounted))"; 

    # KONA
    # HEADER="$HEADER,LocalMem";      LINE="$LINE,${localmem}M";
    HEADER="$HEADER,PF";            LINE="$LINE,${faults}";
    HEADER="$HEADER,AsyncPF";       LINE="$LINE,${afaults}";
    HEADER="$HEADER,ReadPF";       LINE="$LINE,${faultsr}";
    HEADER="$HEADER,WritePF";       LINE="$LINE,${faultsw}";
    # HEADER="$HEADER,WPFaults";      LINE="$LINE,${faultswp}";

    # SHENANGO
    # HEADER="$HEADER,PF(P)";         LINE="$LINE,${pf_posted}";
    # HEADER="$HEADER,PF(R)";         LINE="$LINE,${pf_returned}";
    HEADER="$HEADER,PFTime(s)";      LINE="$LINE,$((pf_time_total_mus/1000000))";
    # HEADER="$HEADER,PFTime(µs)";    LINE="$LINE,${pf_time_each_mus}";
    HEADER="$HEADER,SchedCPU%";     LINE="$LINE,${schedtimepct}";

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