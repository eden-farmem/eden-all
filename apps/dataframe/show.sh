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
-lmp, --lmemper \t results filter: == localmemper\n
-be, --backend \t results filter: == backend\n
-zs, --zipfs \t\t results filter: == zipfs\n
-f, --force \t\t remove any cached data and parse from scratch\n
-b, --basic \t\t just print basic exp info and ignore results (faster!)\n
-g, --good \t\t show just the 'good' runs; definition of good depends on the metrics\n
-rm, --remove \t\t (recoverably) delete runs that match these filters\n
-of, --outfile \t output results to a file instead of stdout\n"

HOST="sc2-hs2-b1630"
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

    -f|--force)
    FORCE=1
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

    -lmp=*|--lmemper=*)
    LMEMPER=${i#*=}
    ;;

    -sc=*|--scheduler=*)
    SCHEDULER="${i#*=}"
    ;;

    -r=*|--rmem=*)
    RMEM="${i#*=}"
    ;;

    -be=*|--backend=*)
    BACKEND="${i#*=}"
    ;;

    -zs=*|--zipfs=*)
    ZIPFS="${i#*=}"
    ;;

    -rd=*|--rdahead=*)
    RDAHEAD="${i#*=}"
    ;;

    -evp=*|--evpolicy=*)
    EVPOL="${i#*=}"
    ;;

    -evpr=*|--evprio=*)
    EVPRIO="${i#*=}"
    ;;

    --evprtype=*)
    EVPRTYPE="${i#*=}"
    ;;

    --lruthr=*)
    LRU_THR="${i#*=}"
    ;;

    -evb=*|--evbatch=*)
    EVBATCH="${i#*=}"
    ;;

    -d=*|--desc=*)
    DESC="${i#*=}"
    ;;

    -b|--basic)
    BASIC=1
    ;;

    -f|--force)
    FORCE=1
    ;;

    -g|--good)
    FILTER_GOOD="${i#*=}"
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
    input=$(cat $exp/settings | grep "input:" | awk -F: '{ print $2 }')
    localmem=$(cat $exp/settings | grep "localmem:" | awk -F: '{ printf $2/1048576 }')
    lmemper=$(cat $exp/settings | grep "lmemper:" | awk -F: '{ printf $2 }')
    rmem=$(cat $exp/settings | grep "rmem:" | awk -F: '{ print $2 }')
    backend=$(cat $exp/settings | grep "backend:" | awk -F: '{ print $2 }')
    rdahead=$(cat $exp/settings | grep "rdahead:" | awk -F: '{ print $2 }')
    evictbs=$(cat $exp/settings | grep "evictbatch:" | awk -F: '{ print $2 }')
    evictpol=$(cat $exp/settings | grep "evictpolicy:" | awk -F: '{ print $2 }')
    evictgens=$(cat $exp/settings | grep "evictgens:" | awk -F: '{ print $2 }')
    evictprio=$(cat $exp/settings | grep "evictprio:" | awk -F: '{ print $2 }')
    evprtype=$(cat $exp/settings | grep "evpriotype:" | awk -F: '{ print $2 }')
    lrubumpthr=$(cat $exp/settings | grep "lrubumpthr:" | awk -F: '{ print $2 }')
    desc=$(cat $exp/settings | grep "desc:" | awk -F: '{ print $2 }')
    input=${input:-none}
    backend=${backend:-none}
    rmem=${rmem:-none}
    evictpol=${evictpol:-NONE}
    evictprio=${evictprio:-no}
    nodirty=${nodirty:-0}
    evprtype=${evprtype:-NONE}

    # apply filters
    if [[ $THREADS ]] && [ "$THREADS" != "$threads" ];      then    continue;   fi
    if [[ $CORES ]] && [ "$CORES" != "$cores" ];            then    continue;   fi
    if [[ $INPUT ]] && [ "$INPUT" != "$input" ];            then    continue;   fi
    if [[ $LOCALMEM ]] && [ "$LOCALMEM" != "$localmem" ];   then    continue;   fi
    if [[ $LMEMPER ]] && [ "$LMEMPER" != "$lmemper" ];      then    continue;   fi
    if [[ $BACKEND ]] && [ "$BACKEND" != "$backend" ];      then    continue;   fi
    if [[ $RMEM ]] && [ "$RMEM" != "$rmem" ];               then    continue;   fi
    if [[ $ZIPFS ]] && [ "$ZIPFS" != "$zipfs" ];            then    continue;   fi
    if [[ $RDAHEAD ]] && [ "$RDAHEAD" != "$rdahead" ];      then    continue;   fi
    if [[ $EVPOL ]] && [ "$EVPOL" != "$evictpol" ];         then    continue;   fi
    if [[ $EVPRIO ]] && [ "$EVPRIO" != "$evictprio" ];      then    continue;   fi
    if [[ $EVPRTYPE ]] && [ "$EVPRTYPE" != "$evprtype" ];   then    continue;   fi
    if [[ $EVBATCH ]] && [ "$EVBATCH" != "$evictbs" ];      then    continue;   fi
    if [[ $LRU_THR ]] && [ "$LRU_THR" != "$lrubumpthr" ];   then    continue;   fi
    if [[ $DESC ]] && [[ "$desc" != "$DESC"  ]];            then    continue;   fi

    if [ -z "$BASIC" ]; then
        # gather numbers
        rstart=
        rend=
        lstart=
        if [ -f ${exp}/load_start ]; then   lstart=$(cat ${exp}/load_start);    fi
        if [ -f ${exp}/run_start ]; then    rstart=$(cat ${exp}/run_start);     fi
        if [ -f ${exp}/run_end ]; then      rend=$(cat ${exp}/run_end);         fi
        rtime=$((rend-rstart))
        ltime=$((rstart-lstart))

        # if runtime is zero, exclude  
        if [[ $FILTER_GOOD ]] && (! [[ $rtime ]] || [ $rtime -le 0 ]); then continue; fi

        if [[ $FORCE ]]; then
            rm -f ${exp}/eden_rmem_parsed
            rm -f ${exp}/runtime_parsed
            rm -f ${exp}/cpu_sar_parsed
            rm -f ${exp}/iokstats_parsed
            rm -f ${exp}/memstat_parsed
            rm -f ${exp}/fstat_parsed
            rm -f ${exp}/cpu_reclaim_sar_parsed
        fi

        # RMEM
        faults=
        faultsr=
        faultsw=
        faultswp=
        kfaultsr=
        kfaultsw=
        kfaultswp=
        kfaults=
        evicts=
        kevicts=
        evpopped=
        hitr=
        if [[ "$rmem" == *"eden"* ]]; then
            edenout=${exp}/eden_rmem_parsed
            edenin=${exp}/rmem-stats.out 
            if [ ! -f $edenout ] && [ -f $edenin ] && [[ $rstart ]] && [[ $rend ]]; then 
                python3 ${ROOT_SCRIPTS_DIR}/parse_eden_rmem.py -i ${edenin}   \
                    -o ${edenout} -st ${rstart} -et ${rend}
            fi
            faultsr=$(csv_column_sum "$edenout" "faults_r")
            faultsw=$(csv_column_sum "$edenout" "faults_w")
            faultswp=$(csv_column_sum "$edenout" "faults_wp")
            faultszp=$(csv_column_sum "$edenout" "faults_zp")
            faults=$(csv_column_sum "$edenout" "faults")
            faultsp0=$(csv_column_sum "$edenout" "faults_p0")
            kfaultsr=$(csv_column_sum "$edenout" "faults_r_h")
            kfaultsw=$(csv_column_sum "$edenout" "faults_w_h")
            kfaultswp=$(csv_column_sum "$edenout" "faults_wp_h")
            # kfaults=$(csv_column_sum "$edenout" "faults_h")
            kfaults=$((kfaultsr+kfaultsw+kfaultswp))
            evicts=$(csv_column_sum "$edenout" "evict_pages_done")
            kevicts=$(csv_column_sum "$edenout" "evict_pages_done_h")
            evpopped=$(csv_column_sum "$edenout" "evict_pages_popped")
            netreads=$(csv_column_sum "$edenout" "net_reads")
            netwrite=$(csv_column_sum "$edenout" "net_writes")
            mallocd=$(csv_column_max "$edenout" "memory_allocd_mb")
            freed=$(csv_column_max "$edenout" "memory_freed_mb")
            steals=$(csv_column_sum "$edenout" "steals")
            hsteals=$(csv_column_sum "$edenout" "steals_h")
            waitretries=$(csv_column_sum "$edenout" "wait_retries")
            hwaitretries=$(csv_column_sum "$edenout" "wait_retries_h")
            madvd=$(csv_column_max "$edenout" "rmadv_size_mb")
            memused=$(csv_column_max "$edenout" "memory_used_mb")
            annothits=$(csv_column_sum "$edenout" "annot_hits")
            reclaimcpu=$(csv_column_sum "$edenout" "cpu_per_h")
            bkendwait=$(csv_column_sum "$edenout" "backend_wait_cycles")
            hitr=
        elif [ "$rmem" == "fastswap" ]; then
            fstat_out=${exp}/fstat_parsed
            fstat_in=${exp}/fstat.out 
            if [ ! -f $fstat_out ] && [ -f $fstat_in ] && [[ $rstart ]] && [[ $rend ]]; then 
                python3 ${ROOT_SCRIPTS_DIR}/parse_fstat.py -i ${fstat_in} \
                    -o ${fstat_out} -st ${rstart} -et ${rend}
            fi
            memstat_out=${exp}/memstat_parsed
            memstat_in=${exp}/memory-stat.out 
            if [ ! -f $memstat_out ] && [ -f $memstat_in ] && [[ $rstart ]] && [[ $rend ]]; then 
                python3 ${ROOT_SCRIPTS_DIR}/parse_memory_stat.py -i ${memstat_in} \
                    -o ${memstat_out} -st ${rstart} -et ${rend}
            fi
            faults=$(csv_column_sum "$memstat_out" "pgfault")
            majfaults=$(csv_column_sum "$memstat_out" "pgmajfault")
            minfaults=$((faults-majfaults))
            faults=$majfaults
            memused=$(csv_column_max "$memstat_out" "anon_mb")
            netreads=$(csv_column_sum "$fstat_out" "loads")
            netwrite=$(csv_column_sum "$fstat_out" "succ_stores")
            mallocd=
            freed=

            # reclaim cpu
            cpusarout=${exp}/cpu_reclaim_sar_parsed
            cpusarin=${exp}/cpu_reclaim.sar
            if [ ! -f $cpusarout ] && [ -f $cpusarin ] && [[ $rstart ]] && [[ $rend ]]; then 
                bash ${ROOT_SCRIPTS_DIR}/parse_sar.sh -sf=${cpusarin} -sc="%system" \
                    -st=${rstart} -et=${rend} -of=${cpusarout}
            fi
            reclaimcpu=$(csv_column_mean "$cpusarout" "%system")
        fi

        # SHENANGO
        shenangoout=${exp}/runtime_parsed
        shenangoin=${exp}/runtime.out 
        if ([[ $FORCE ]] || [ ! -f $shenangoout ]) && [ -f $shenangoin ]; then 
            python3 ${ROOT_SCRIPTS_DIR}/parse_shenango_runtime.py -i ${shenangoin}   \
                -o ${shenangoout}  -st=${rstart} -et=${rend} 
        fi
        sched_idle_cycles=$(csv_column_mean "$shenangoout" "sched_cycles_idle")
        sched_time_cycles=$(csv_column_mean "$shenangoout" "sched_cycles")
        app_time_cycles=$(csv_column_mean "$shenangoout" "program_cycles")
        rescheds=$(csv_column_mean "$shenangoout" "rescheds")
        parks=$(csv_column_mean "$shenangoout" "parks")
        softirqs=$(csv_column_mean "$shenangoout" "softirqs")
        thsteals=$(csv_column_mean "$shenangoout" "threads_stolen")
        irqsteals=$(csv_column_mean "$shenangoout" "softirqs_stolen")
    fi

    # write
    HEADER="Exp";                   LINE="$name";
    HEADER="$HEADER,RMem";          LINE="$LINE,${rmem}";
    HEADER="$HEADER,Backend";       LINE="$LINE,${backend}";
    HEADER="$HEADER,CPU";           LINE="$LINE,${cores}";
    HEADER="$HEADER,Threads";       LINE="$LINE,${threads}";
    HEADER="$HEADER,Input";         LINE="$LINE,${input}";
    HEADER="$HEADER,Local_MB";      LINE="$LINE,${localmem}";
    HEADER="$HEADER,LMem%";         LINE="$LINE,${lmemper}";
    HEADER="$HEADER,RdHd";          LINE="$LINE,${rdahead}";
    HEADER="$HEADER,EvB";           LINE="$LINE,${evictbs}";
    HEADER="$HEADER,EvP";           LINE="$LINE,${evictpol}";
    HEADER="$HEADER,EvPr";          LINE="$LINE,${evictprio}";
    # HEADER="$HEADER,EvG";           LINE="$LINE,${evictgens}";
    if [ -z "$BASIC" ]; then
        HEADER="$HEADER,LoadTime";      LINE="$LINE,${ltime}";
        HEADER="$HEADER,Runtime";       LINE="$LINE,${rtime}";
        HEADER="$HEADER,Faults";        LINE="$LINE,${faults}";
        HEADER="$HEADER,FaultsNoZP";    LINE="$LINE,$((faults-faultszp))";
        HEADER="$HEADER,FaultsR";       LINE="$LINE,${faultsr}";
        # HEADER="$HEADER,FaultsW";       LINE="$LINE,${faultsw}";
        # HEADER="$HEADER,FaultsWP";      LINE="$LINE,${faultswp}";
        HEADER="$HEADER,FaultsZP";      LINE="$LINE,${faultszp}";
        HEADER="$HEADER,FaultsP0";      LINE="$LINE,${faultsp0}";
        HEADER="$HEADER,KFaults";       LINE="$LINE,${kfaults}";
        HEADER="$HEADER,KFaults%"       LINE="$LINE,$((kfaults*100/(faults+1)))";
        HEADER="$HEADER,KFaultsR";      LINE="$LINE,${kfaultsr}";
        HEADER="$HEADER,KFaultsW";      LINE="$LINE,${kfaultsw}";
        HEADER="$HEADER,KFaultsWP";     LINE="$LINE,${kfaultswp}";
        HEADER="$HEADER,Evicts";        LINE="$LINE,${evicts}";
        HEADER="$HEADER,KEvicts";       LINE="$LINE,${kevicts}";
        HEADER="$HEADER,EvPopped";      LINE="$LINE,${evpopped}";
        HEADER="$HEADER,AnnotHits";     LINE="$LINE,${annothits}";
        HEADER="$HEADER,HitR";          LINE="$LINE,${hitr}";

        HEADER="$HEADER,NetReads";      LINE="$LINE,${netreads}";
        HEADER="$HEADER,NetWrites";     LINE="$LINE,${netwrite}";
        HEADER="$HEADER,rCPU%";         LINE="$LINE,${reclaimcpu}";
        HEADER="$HEADER,Mallocd";       LINE="$LINE,${mallocd}";
        HEADER="$HEADER,Freed";       LINE="$LINE,${freed}";
        HEADER="$HEADER,MemUsed";       LINE="$LINE,${memused}M";

        # steals
        HEADER="$HEADER,RSteals";       LINE="$LINE,${rsteals}";
        HEADER="$HEADER,WSteals";       LINE="$LINE,${wsteals}";
        HEADER="$HEADER,HRSteals";      LINE="$LINE,${hrsteals}";
        HEADER="$HEADER,WRSteals";      LINE="$LINE,${wrsteals}";
        HEADER="$HEADER,WaitRetries";   LINE="$LINE,${waitretries}";

        # Shenango
        HEADER="$HEADER,Idle(ms)";      LINE="$LINE,$((sched_idle_cycles/(cores*2194*1000)))";
        HEADER="$HEADER,BkIdle(ms)";    LINE="$LINE,$((bkendwait/(cores*2194*1000)))";
        HEADER="$HEADER,Rtime(ms)";     LINE="$LINE,$((sched_time_cycles/(cores*2194*1000)))";
        HEADER="$HEADER,Ptime(ms)";     LINE="$LINE,$((app_time_cycles/(cores*2194*1000)))";
        HEADER="$HEADER,Rescheds";      LINE="$LINE,${rescheds}";
        HEADER="$HEADER,RTentries";     LINE="$LINE,${parks}";
        HEADER="$HEADER,Softirqs";      LINE="$LINE,${softirqs}";
        HEADER="$HEADER,Steals";        LINE="$LINE,${thsteals}";
        HEADER="$HEADER,IRQSteals";     LINE="$LINE,${irqsteals}";
    fi

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