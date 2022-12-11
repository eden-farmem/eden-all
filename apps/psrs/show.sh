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
-lmp, --lmemper \t results filter: == localmemper\n
-be, --backend \t results filter: == backend\n
-pf, --pgfaults \t results filter: == pgfaults\n
-d, --desc \t\t results filter: contains desc\n
-tg, --tag \t\t results filter: == tag\n
-f, --force \t\t remove any cached data and parse from scratch\n
-s, --simple \t\t print basic info on the runs, no need to get all metrics (its faster)\n
-v, --verbose \t\t print all columns available (when gathering to file)\n
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

    -pf=*|--pgfaults=*)
    PGFAULTS="${i#*=}"
    ;;

    -zs=*|--zipfs=*)
    ZIPFS="${i#*=}"
    ;;

    -d=*|--desc=*)
    DESC="${i#*=}"
    ;;

    -rd=*|--rdahead=*)
    RDAHEAD="${i#*=}"
    ;;

    -mrd=*|--mrdahead=*)
    MGRDAHEAD="${i#*=}"
    ;;

    -tg=*|--tag=*)
    TAG="${i#*=}"
    ;;

    -f|--force)
    FORCE=1
    ;;

    -s|--simple)
    SIMPLE=1
    ;;

    -v|--verbose)
    VERBOSE=1
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
    localmem=$(cat $exp/settings | grep "localmem:" | awk -F: '{ printf $2/1048576 }')
    lmemper=$(cat $exp/settings | grep "lmemper:" | awk -F: '{ printf $2 }')
    rmem=$(cat $exp/settings | grep "rmem:" | awk -F: '{ print $2 }')
    sched=$(cat $exp/settings | grep "scheduler:" | awk -F: '{ print $2 }')
    backend=$(cat $exp/settings | grep "backend:" | awk -F: '{ print $2 }')
    nkeys=$(cat $exp/settings | grep "keys:" | awk -F: '{ print $2 }')
    rdahead=$(cat $exp/settings | grep "^rdahead:" | awk -F: '{ print $2 }')
    mgrdahead=$(cat $exp/settings | grep "^mergerdahead:" | awk -F: '{ print $2 }')
    evictbs=$(cat $exp/settings | grep "evictbatch:" | awk -F: '{ print $2 }')
    evictpol=$(cat $exp/settings | grep "evictpolicy:" | awk -F: '{ print $2 }')
    evictgens=$(cat $exp/settings | grep "evictgens:" | awk -F: '{ print $2 }')
    evictgens=$(cat $exp/settings | grep "evictgens:" | awk -F: '{ print $2 }')
    vdso=$(cat $exp/settings | grep "vdso:" | awk -F: '{ print $2 }')
    tag=$(cat $exp/settings | grep "tag:" | awk -F: '{ print $2 }')
    desc=$(cat $exp/settings | grep "desc:" | awk -F: '{ print $2 }')
    sched=${sched:-none}
    backend=${backend:-none}
    rmem=${rmem:-none}
    tag=${tag:-none}
    vdso=${vdso:-0}
    desc=${desc:-none}
    mgrdahead=${mgrdahead:-$rdahead}

    # apply filters
    if [[ $THREADS ]] && [ "$THREADS" != "$threads" ];      then    continue;   fi
    if [[ $CORES ]] && [ "$CORES" != "$cores" ];            then    continue;   fi
    if [[ $NKEYS ]] && [ "$NKEYS" != "$nkeys" ];            then    continue;   fi
    if [[ $LOCALMEM ]] && [ "$LOCALMEM" != "$localmem" ];   then    continue;   fi
    if [[ $LMEMPER ]] && [ "$LMEMPER" != "$lmemper" ];      then    continue;   fi
    if [[ $BACKEND ]] && [ "$BACKEND" != "$backend" ];      then    continue;   fi
    if [[ $RMEM ]] && [ "$RMEM" != "$rmem" ];               then    continue;   fi
    if [[ $SCHEDULER ]] && [ "$SCHEDULER" != "$sched" ];    then    continue;   fi
    if [[ $BACKEND ]] && [ "$BACKEND" != "$backend" ];      then    continue;   fi
    if [[ $RDAHEAD ]] && [ "$RDAHEAD" != "$rdahead" ];      then    continue;   fi
    if [[ $MGRDAHEAD ]] && [ "$MGRDAHEAD" != "$mgrdahead" ];then    continue;   fi
    if [[ $DESC ]] && [[ "$desc" != "$DESC"  ]];            then    continue;   fi
    if [[ $TAG ]] && [[ "$tag" != "$TAG"  ]];               then    continue;   fi
    
    ## PERFORMANCE BREAKDOWN

    # APPLICATION LOGS
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

    # SETTINGS
    HEADER=;                        LINE=;
    HEADER="$HEADER,Exp";           LINE="$LINE,$name";
    HEADER="$HEADER,Scheduler";     LINE="$LINE,${sched}";
    HEADER="$HEADER,RMem";          LINE="$LINE,${rmem}";
    HEADER="$HEADER,Backend";       LINE="$LINE,${backend}";
    # HEADER="$HEADER,Tag";           LINE="$LINE,${tag}";
    # HEADER="$HEADER,Keys";        LINE="$LINE,$((nkeys/1000000))M";
    HEADER="$HEADER,CPU";           LINE="$LINE,${cores}";
    HEADER="$HEADER,Thr";           LINE="$LINE,${threads}";
    HEADER="$HEADER,LocalMem";      LINE="$LINE,${localmem}M";
    HEADER="$HEADER,LMem%";         LINE="$LINE,${lmemper}";
    HEADER="$HEADER,RdHd";          LINE="$LINE,${rdahead}";
    HEADER="$HEADER,MRdHd";         LINE="$LINE,${mgrdahead}";
    HEADER="$HEADER,EvB";           LINE="$LINE,${evictbs}";
    # HEADER="$HEADER,EvP";           LINE="$LINE,${evictpol}";
    # HEADER="$HEADER,VDSO";           LINE="$LINE,${vdso}";
    # HEADER="$HEADER,EvG";           LINE="$LINE,${evictgens}";

    # OVERALL PERF
    HEADER="$HEADER,Time(s)";       LINE="$LINE,$((rtime))";
    # HEADER="$HEADER,Work";          LINE="$LINE,${cpuwork}";
    HEADER="$HEADER,Phase1";        LINE="$LINE,$((p1time))";
    # HEADER="$HEADER,Phase2";        LINE="$LINE,$((p2time))";
    HEADER="$HEADER,Phase3";        LINE="$LINE,$((p3time))";
    HEADER="$HEADER,Phase4";        LINE="$LINE,$((p4time))";
    HEADER="$HEADER,Copyback";      LINE="$LINE,$((copyback))";
    HEADER="$HEADER,Unacc";         LINE="$LINE,$((unaccounted))"; 

    # PERFORMANCE BREAKDOWN
    if ! [[ $SIMPLE ]]; then 
        # for kind in "total" "phase1" "phase2" "phase3" "phase4" "copyback"; do 
        for kind in "T" "p1" "p2" "p3" "p4" "cb"; do 
            case $kind in
            "T")        start=`cat ${exp}/phase1`;      end=`cat ${exp}/end`;       v=1 ;;
            "p1")       start=`cat ${exp}/phase1`;      end=`cat ${exp}/phase2`;    v=  ;;
            "p2")       start=`cat ${exp}/phase2`;      end=`cat ${exp}/phase3`;    v=  ;;
            "p3")       start=`cat ${exp}/phase3`;      end=`cat ${exp}/phase4`;    v=  ;;
            "p4")       start=`cat ${exp}/phase4`;      end=`cat ${exp}/copyback`;  v=  ;;
            "cb")       start=`cat ${exp}/copyback`;    end=`cat ${exp}/end`;       v=  ;;
            *)              echo "Unknown kind"; exit;;
            esac

            time=$((end-start))
            sflag_py="--start ${start}"
            sflag_sh="--start=${start}"    
            eflag_py="--end ${end}"        
            eflag_sh="--end=${end}"

            vmstat_out=${exp}/vmstat_parsed_${kind}
            vmstat_in=${exp}/vmstat.out 
            if [ ! -f $vmstat_out ] && [ -f $vmstat_in ]; then 
                python3 ${ROOT_SCRIPTS_DIR}/parse_vmstat.py -i ${vmstat_in} \
                    -o ${vmstat_out}  ${sflag_sh} ${eflag_sh} 
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
            annothits=
            if [[ "$rmem" == *"eden"* ]]; then
                edenout=${exp}/eden_rmem_parsed_${kind}
                edenin=${exp}/rmem-stats.out 
                if [ ! -f $edenout ] && [ -f $edenin ]; then 
                    python3 ${ROOT_SCRIPTS_DIR}/parse_eden_rmem.py -i ${edenin}   \
                        -o ${edenout}  ${sflag_sh} ${eflag_sh}
                fi
                faults=$(csv_column_sum "$edenout" "faults")
                faultsr=$(csv_column_sum "$edenout" "faults_r")
                faultsw=$(csv_column_sum "$edenout" "faults_w")
                faultswp=$(csv_column_sum "$edenout" "faults_wp")
                faultszp=$(csv_column_sum "$edenout" "faults_zp")
                kfaultsr=$(csv_column_sum "$edenout" "faults_r_h")
                kfaultsw=$(csv_column_sum "$edenout" "faults_w_h")
                kfaultswp=$(csv_column_sum "$edenout" "faults_wp_h")
                kfaults=$(csv_column_sum "$edenout" "faults_h")
                evicts=$(csv_column_sum "$edenout" "evict_pages_done")
                kevicts=$(csv_column_sum "$edenout" "evict_pages_done_h")
                evpopped=$(csv_column_sum "$edenout" "evict_pages_popped")
                netreads=$(csv_column_sum "$edenout" "net_reads")
                netwrite=$(csv_column_sum "$edenout" "net_writes")
                mallocd=$(csv_column_max "$edenout" "rmalloc_size")
                annothits=$(csv_column_sum "$edenout" "annot_hits")
                # steals=$(csv_column_mean "$edenout" "steals")
                # hsteals=$(csv_column_mean "$edenout" "steals_h")
                # waitretries=$(csv_column_mean "$edenout" "wait_retries")
                # hwaitretries=$(csv_column_mean "$edenout" "wait_retries_h")
                # madvd=$(csv_column_max "$edenout" "rmadv_size")
                memused=$(csv_column_max "$edenout" "memory_used_mb")            hitr=
                if [[ $annothits ]] && [[ $faults ]]; then 
                    hitr=$(percentage "$((annothits-faults))" "$annothits" | ftoi)
                fi
            elif [ "$rmem" == "fastswap" ]; then
                fstat_out=${exp}/fstat_parsed_${kind}
                fstat_in=${exp}/fstat.out 
                if [ ! -f $fstat_out ] && [ -f $fstat_in ]; then 
                    python3 ${ROOT_SCRIPTS_DIR}/parse_fstat.py -i ${fstat_in} \
                        -o ${fstat_out}  ${sflag_sh} ${eflag_sh} 
                fi
                vmstat_out=${exp}/vmstat_parsed_${kind}
                vmstat_in=${exp}/vmstat.out 
                if [ ! -f $vmstat_out ] && [ -f $vmstat_in ]; then 
                    python3 ${ROOT_SCRIPTS_DIR}/parse_vmstat.py -i ${vmstat_in} \
                        -o ${vmstat_out}  ${sflag_sh} ${eflag_sh} 
                fi
                faults=$(csv_column_sum "$vmstat_out" "pgmajfault")
                memused=$(csv_column_max "$vmstat_out" "nr_anon_pages_mb")
                faultsm=$(csv_column_sum "$vmstat_out" "pgfault")
                netreads=$(csv_column_sum "$fstat_out" "loads")
                netwrite=$(csv_column_sum "$fstat_out" "succ_stores")
            fi

            # SHENANGO
            shenangoout=${exp}/runtime_parsed_${kind}
            shenangoin=${exp}/runtime.out 
            if ([[ $FORCE ]] || [ ! -f $shenangoout ]) && [ -f $shenangoin ]; then 
                python ${ROOT_SCRIPTS_DIR}/parse_shenango_runtime.py -i ${shenangoin}   \
                    -o ${shenangoout} ${sflag_py} ${eflag_py}
            fi
            sched_time_us=$(csv_column_sum "$shenangoout" "sched_time_us")
            user_idle_us=$(csv_column_sum "$shenangoout" "sched_idle_us")

            # KERNEL
            cpusarout=${exp}/cpu_sar_parsed_${kind}
            cpusarin=${exp}/cpu.sar
            if ([[ $FORCE ]] || [ ! -f $cpusarout ]) && [ -f $cpusarin ]; then 
                bash ${ROOT_SCRIPTS_DIR}/parse_sar.sh -sf=${exp}/cpu.sar -sc="%user" \
                    ${sflag_sh} ${eflag_sh} -of=${cpusarout}
            fi
            kernel_idle_per=$(csv_column_sum "$cpusarout" "%idle")
            kernel_idle_us=$((kernel_idle_per*10000))
            total_idle_us=$((user_idle_us+kernel_idle_us))

            # Verbose
            if [[ $v ]]; then 
                HEADER="$HEADER,PF";                LINE="$LINE,${faults}";
                # HEADER="$HEADER,AllPF";           LINE="$LINE,${faultsm}";
                HEADER="$HEADER,KernPF";            LINE="$LINE,${kfaults}";
                # HEADER="$HEADER,ReadPF";            LINE="$LINE,${faultsr}";
                # HEADER="$HEADER,WritePF";           LINE="$LINE,${faultsw}";
                # HEADER="$HEADER,WPFaults";          LINE="$LINE,${faultswp}";
                HEADER="$HEADER,Evicts";          LINE="$LINE,${evicts}";
                HEADER="$HEADER,KEvicts";         LINE="$LINE,${kevicts}";
                HEADER="$HEADER,EvPopped";        LINE="$LINE,${evpopped}";
                # HEADER="$HEADER,HitR";            LINE="$LINE,${hitr}";
                # HEADER="$HEADER,NetReads";        LINE="$LINE,${netreads}";
                # HEADER="$HEADER,NetWrites";       LINE="$LINE,${netwrite}";
                HEADER="$HEADER,rCPU%";             LINE="$LINE,${reclaimcpu}";
                # HEADER="$HEADER,Mallocd";           LINE="$LINE,$((mallocd/(1024*1024)))M";
                HEADER="$HEADER,MemUsed";           LINE="$LINE,${memused}M";
            fi

            # Condensed columns
            uidle=$((user_idle_us/1000000))
            kidle=$((kernel_idle_us/1000000))
            tidle=$((total_idle_us/1000000))
            if [[ $VERBOSE ]]; then 
                HEADER="$HEADER,Time($kind)";         LINE="$LINE,${time}";
                HEADER="$HEADER,Idle($kind)";         LINE="$LINE,${tidle}";
                HEADER="$HEADER,UIdle($kind)";        LINE="$LINE,${uidle}";
                HEADER="$HEADER,KIdle($kind)";        LINE="$LINE,${kidle}";
                HEADER="$HEADER,HitR($kind)";         LINE="$LINE,${hitr}";
                HEADER="$HEADER,Flts($kind)";         LINE="$LINE,${faults}";
                HEADER="$HEADER,Evicts($kind)";       LINE="$LINE,${evicts}";
            fi

            # HEADER="$HEADER,HitR($kind)";           LINE="$LINE,${hitr}";
            HEADER="$HEADER,Idle($kind)";           LINE="$LINE,${uidle}|${kidle}";
            # HEADER="$HEADER,PF($kind)";             LINE="$LINE,${faultszp}";
            # HEADER="$HEADER,PF($kind)";             LINE="$LINE,${faults}";
            # faultsf=$(echo $faults | awk '{
            #     if ($0>=1000000)    printf "%.1fM", $0*1.0/1000000;
            #     else                printf "%.1fK", $0*1.0/1000; }') 
            # HEADER="$HEADER,Flts($kind)";       LINE="$LINE,${faultsf}";
        done
    fi

    # OTHER
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