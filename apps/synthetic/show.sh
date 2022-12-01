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
-pf, --pgfaults \t results filter: == pgfaults\n
-pc, --pgchecks \t results filter: == pgchecks\n
-zs, --zipfs \t\t results filter: == zipfs\n
-f, --force \t\t remove any cached data and parse from scratch\n
-b, --basic \t\t just print basic exp info and ignore results (faster!)\n
-g, --good \t\t show just the 'good' runs; definition of good depends on the metrics\n
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
    localmem=$(cat $exp/settings | grep "localmem:" | awk -F: '{ printf $2/1048576 }')
    lmemper=$(cat $exp/settings | grep "lmemper:" | awk -F: '{ printf $2 }')
    rmem=$(cat $exp/settings | grep "rmem:" | awk -F: '{ print $2 }')
    sched=$(cat $exp/settings | grep "scheduler:" | awk -F: '{ print $2 }')
    backend=$(cat $exp/settings | grep "backend:" | awk -F: '{ print $2 }')
    nkeys=$(cat $exp/settings | grep "keys:" | awk -F: '{ print $2 }')
    nblobs=$(cat $exp/settings | grep "blobs:" | awk -F: '{ print $2 }')
    zipfs=$(cat $exp/settings | grep "zipfs:" | awk -F: '{ print $2 }')
    rdahead=$(cat $exp/settings | grep "rdahead:" | awk -F: '{ print $2 }')
    evictbs=$(cat $exp/settings | grep "evictbatch:" | awk -F: '{ print $2 }')
    evictpol=$(cat $exp/settings | grep "evictpolicy:" | awk -F: '{ print $2 }')
    evictgens=$(cat $exp/settings | grep "evictgens:" | awk -F: '{ print $2 }')
    desc=$(cat $exp/settings | grep "desc:" | awk -F: '{ print $2 }')
    sched=${sched:-none}
    backend=${backend:-none}
    rmem=${rmem:-none}
    evictpol=${evictpol:-NONE}

    # apply filters
    if [[ $THREADS ]] && [ "$THREADS" != "$threads" ];      then    continue;   fi
    if [[ $CORES ]] && [ "$CORES" != "$cores" ];            then    continue;   fi
    if [[ $LOCALMEM ]] && [ "$LOCALMEM" != "$localmem" ];   then    continue;   fi
    if [[ $LMEMPER ]] && [ "$LMEMPER" != "$lmemper" ];      then    continue;   fi
    if [[ $BACKEND ]] && [ "$BACKEND" != "$backend" ];      then    continue;   fi
    if [[ $RMEM ]] && [ "$RMEM" != "$rmem" ];               then    continue;   fi
    if [[ $SCHEDULER ]] && [ "$SCHEDULER" != "$sched" ];    then    continue;   fi
    if [[ $ZIPFS ]] && [ "$ZIPFS" != "$zipfs" ];            then    continue;   fi
    if [[ $RDAHEAD ]] && [ "$RDAHEAD" != "$rdahead" ];      then    continue;   fi
    if [[ $EVPOL ]] && [ "$EVPOL" != "$evictpol" ];         then    continue;   fi
    if [[ $EVBATCH ]] && [ "$EVBATCH" != "$evictbs" ];      then    continue;   fi
    if [[ $DESC ]] && [[ "$desc" != "$DESC"  ]];            then    continue;   fi
    
    if [ -z "$BASIC" ]; then
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

        # if runtime is zero, exclude  
        if [[ $FILTER_GOOD ]] && (! [[ $rtime ]] || [ $rtime -le 0 ]); then continue; fi

        if [[ $FORCE ]]; then
            rm -f ${exp}/eden_rmem_parsed
            rm -f ${exp}/runtime_parsed
            rm -f ${exp}/cpu_sar_parsed
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
            faultsr=$(csv_column_mean "$edenout" "faults_r")
            faultsw=$(csv_column_mean "$edenout" "faults_w")
            faultswp=$(csv_column_mean "$edenout" "faults_wp")
            faults=$(csv_column_mean "$edenout" "faults")
            kfaultsr=$(csv_column_mean "$edenout" "faults_r_h")
            kfaultsw=$(csv_column_mean "$edenout" "faults_w_h")
            kfaultswp=$(csv_column_mean "$edenout" "faults_wp_h")
            # kfaults=$(csv_column_mean "$edenout" "faults_h")
            kfaults=$((kfaultsr+kfaultsw+kfaultswp))
            evicts=$(csv_column_mean "$edenout" "evict_pages_done")
            kevicts=$(csv_column_mean "$edenout" "evict_pages_done_h")
            evpopped=$(csv_column_mean "$edenout" "evict_pages_popped")
            netreads=$(csv_column_mean "$edenout" "net_reads")
            netwrite=$(csv_column_mean "$edenout" "net_writes")
            mallocd=$(csv_column_max "$edenout" "rmalloc_size")
            steals=$(csv_column_mean "$edenout" "steals")
            hsteals=$(csv_column_mean "$edenout" "steals_h")
            waitretries=$(csv_column_mean "$edenout" "wait_retries")
            hwaitretries=$(csv_column_mean "$edenout" "wait_retries_h")
            # madvd=$(csv_column_max "$edenout" "rmadv_size")
            annothits=$(csv_column_mean "$edenout" "annot_hits")
            hitr=
            if [[ $annothits ]] && [[ $faults ]]; then 
                hitr=$(percentage "$((annothits-faults))" "$annothits" | ftoi)
            fi
        elif [ "$rmem" == "fastswap" ]; then
            fstat_out=${exp}/fstat_parsed
            fstat_in=${exp}/fstat.out 
            if [ ! -f $fstat_out ] && [ -f $fstat_in ] && [[ $rstart ]] && [[ $rend ]]; then 
                python3 ${ROOT_SCRIPTS_DIR}/parse_fstat.py -i ${fstat_in} \
                    -o ${fstat_out} -st ${rstart} -et ${rend}
            fi
            vmstat_out=${exp}/vmstat_parsed
            vmstat_in=${exp}/vmstat.out 
            if [ ! -f $vmstat_out ] && [ -f $vmstat_in ] && [[ $rstart ]] && [[ $rend ]]; then 
                python3 ${ROOT_SCRIPTS_DIR}/parse_vmstat.py -i ${vmstat_in} \
                    -o ${vmstat_out} -st ${rstart} -et ${rend}
            fi
            faults=$(csv_column_mean "$vmstat_out" "pgmajfault")
            netreads=$(csv_column_mean "$fstat_out" "loads")
            netwrite=$(csv_column_mean "$fstat_out" "succ_stores")
        fi

        # SHENANGO
        # shenangoout=${exp}/runtime_parsed
        # shenangoin=${exp}/runtime.out 
        # if [ ! -f $shenangoout ] && [ -f $shenangoin ] && [[ $rstart ]] && [[ $rend ]]; then 
        #     python ${ROOT_SCRIPTS_DIR}/parse_shenango_runtime.py -i ${shenangoin}   \
        #         -o ${shenangoout} -st=${rstart} -et ${rend}
        # fi
        # user_idle_per=$(csv_column_mean "$shenangoout" "sched_idle_per")
        # pf_annot_hits=$(csv_column_mean "$shenangoout" "pf_annot_hits")
        # pf_posted=$(csv_column_mean "$shenangoout" "pf_posted")
        # # pf_annot_hitr=$(percentage "$pf_annot_hits" "$((pf_posted+pf_annot_hits))" | ftoi)
        # # pf_annot_hitpm=$(percentage $pf_annot_hits $pf_posted | ftoi)
        # hitcost=30; misscost=1400;  #vdso
        # if [ "$pgchecks" == "kona" ]; then  hitcost=120; misscost=120; fi
        # annot_hitcost_ms=$((pf_annot_hits*hitcost/1000000))
        # annot_misscost_ms=$((pf_posted*misscost/1000000))
        # annot_hit_overhd=$((annot_hitcost_ms*xput/1000))
        # annot_miss_overhd=$((annot_misscost_ms*xput/1000))
        # xput_accounted=$((xput+annot_hit_overhd+annot_miss_overhd))

        # # KERNEL
        # cpusarout=${exp}/cpu_sar_parsed
        # cpusarin=${exp}/cpu.sar
        # if [ ! -f $cpusarout ] && [ -f $cpusarin ] && [[ $rstart ]] && [[ $rend ]]; then 
        #     bash ${ROOT_SCRIPTS_DIR}/parse_sar.sh -sf=${exp}/cpu.sar -sc="%idle" \
        #         -st=${rstart} -et=${rend} -of=${cpusarout}
        # fi
        # kernel_idle_per=$(csv_column_mean "$cpusarout" "%idle")
    fi

    # write
    HEADER="Exp";                   LINE="$name";
    # HEADER="$HEADER,Scheduler";     LINE="$LINE,${sched}";
    HEADER="$HEADER,RMem";          LINE="$LINE,${rmem}";
    HEADER="$HEADER,Backend";       LINE="$LINE,${backend}";
    HEADER="$HEADER,CPU";           LINE="$LINE,${cores}";
    HEADER="$HEADER,Threads";       LINE="$LINE,${threads}";
    HEADER="$HEADER,Local_MB";      LINE="$LINE,${localmem}";
    HEADER="$HEADER,LMem%";         LINE="$LINE,${lmemper}";
    HEADER="$HEADER,ZipfS";         LINE="$LINE,${zipfs}";
    HEADER="$HEADER,RdHd";          LINE="$LINE,${rdahead}";
    HEADER="$HEADER,EvB";           LINE="$LINE,${evictbs}";
    HEADER="$HEADER,EvP";           LINE="$LINE,${evictpol}";
    # HEADER="$HEADER,EvG";           LINE="$LINE,${evictgens}";
    if [ -z "$BASIC" ]; then
        # HEADER="$HEADER,PreloadTime";   LINE="$LINE,${ptime}";
        # HEADER="$HEADER,Runtime";       LINE="$LINE,${rtime}";
        HEADER="$HEADER,Xput";          LINE="$LINE,${xput:-}";
        # HEADER="$HEADER,XputPerCore";   LINE="$LINE,${xputpercore}";
        HEADER="$HEADER,Faults";        LINE="$LINE,${faults}";
        HEADER="$HEADER,FaultsR";       LINE="$LINE,${faultsr}";
        # HEADER="$HEADER,FaultsW";       LINE="$LINE,${faultsw}";
        HEADER="$HEADER,FaultsWP";      LINE="$LINE,${faultswp}";
        HEADER="$HEADER,KFaults";       LINE="$LINE,${kfaults}";
        HEADER="$HEADER,Evicts";        LINE="$LINE,${evicts}";
        HEADER="$HEADER,KEvicts";       LINE="$LINE,${kevicts}";
        HEADER="$HEADER,EvPopped";      LINE="$LINE,${evpopped}";
        HEADER="$HEADER,HitR";          LINE="$LINE,${hitr}";

        # HEADER="$HEADER,NetReads";      LINE="$LINE,${netreads}";
        # HEADER="$HEADER,NetWrites";     LINE="$LINE,${netwrite}";
        # HEADER="$HEADER,Mallocd";       LINE="$LINE,${mallocd}";
        # HEADER="$HEADER,MaxRSS";      LINE="$LINE,$((mempressure/1048576))M";
        # HEADER="$HEADER,Steals";      LINE="$LINE,${steals}";
        # HEADER="$HEADER,HSteals";      LINE="$LINE,${hsteals}";
        # HEADER="$HEADER,Waits";       LINE="$LINE,${waitretries}";
        # HEADER="$HEADER,HWaits";       LINE="$LINE,${hwaitretries}";

        # HEADER="$HEADER,UFFDCopy";      LINE="$LINE,${uffd_copy_cost}";
        # HEADER="$HEADER,UIdle%";        LINE="$LINE,${user_idle_per}";
        # HEADER="$HEADER,KIdle%";        LINE="$LINE,${kernel_idle_per}";
        # HEADER="$HEADER,AnnotHit";      LINE="$LINE,$((pf_annot_hits+pf_posted))";
        # HEADER="$HEADER,AnnotMiss";     LINE="$LINE,${pf_posted}";
        # HEADER="$HEADER,XputAcc";       LINE="$LINE,${xput_accounted}";
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