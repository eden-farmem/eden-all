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
-of, --outfile \t output results to a file instead of stdout\n"

HOST="sc2-hs2-b1630"
CLIENT="sc2-hs2-b1632"

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
    LS_CMD=`ls -d1 data/run-${SUFFIX}*/`
    SUFFIX=$SUFFIX
elif [[ $CSUFFIX ]]; then
    LS_CMD=`ls -d1 data/*/ | grep -e "$CSUFFIX"`
    SUFFIX=$CSUFFIX
else 
    SUFFIX=$(date +"%m-%d")     # default to today
    LS_CMD=`ls -d1 data/run-${SUFFIX}*/`
fi
# echo $LS_CMD

for exp in $LS_CMD; do
    # config
    # echo $exp
    name=`basename $exp`
    cores=$(cat $exp/settings | grep "cores" | awk -F: '{ print $2 }')
    threads=$(cat $exp/settings | grep "threads" | awk -F: '{ print $2 }')
    localmem=$(cat $exp/settings | grep "localmem" | awk -F: '{ printf $2/1000000 }')
    backend=$(cat $exp/settings | grep "backend" | awk -F: '{ print $2 }')
    desc=$(cat $exp/settings | grep "desc" | awk -F: '{ print $2 }')

    # apply filters
    if [[ $THREADS ]] && [ "$THREADS" != "$threads" ];  then    continue;   fi
    if [[ $CORES ]] && [ "$CORES" != "$cores" ];        then    continue;   fi
    if [[ $LOCALMEM ]] && [ "$LOCALMEM" != "$localmem" ];   then    continue;   fi
    if [[ $DESC ]] && [[ "$readme" != *"$DESC"*  ]];    then    continue;   fi

    # run time
    sample_start=$(cat $exp/sample_start 2>/dev/null)
    sample_end=$(cat $exp/sample_end 2>/dev/null)
    stime=$((sample_end-sample_start))
    sxput=$(cat $exp/app.out 2>/dev/null | grep "result:" | sed 's/result://' | awk -F, '{ print $2 }')

    # other stats
    rss=$(cat $exp/app.out 2>/dev/null | grep "Maximum resident set size" | awk -F: '{ print $2 }' | xargs)
    pgfmajor=$(cat $exp/app.out 2>/dev/null | grep "Major .* page faults" | awk -F: '{ print $2 }' | xargs)
    pgfminor=$(cat $exp/app.out 2>/dev/null | grep "Minor .* page faults" | awk -F: '{ print $2 }' | xargs)
    cpuper=$(cat $exp/app.out 2>/dev/null | grep "Percent of CPU" | awk -F: '{ print $2 }' | xargs)
    pgfminor=$(cat $exp/app.out 2>/dev/null | grep "Minor .* page faults" | awk -F: '{ print $2 }' | xargs)

    # # pgfaults - specific
    # pgfile=$exp/sar_pgfaults_majflts
    # if [ ! -f $pgfile ]; then bash parse_sar.sh -n=${name} -sf=pgfaults -sc=majflt/s -t1=$sample_start -t2=$sample_end -of=$pgfile; fi
    # majpgfrate=$(tail -n+2 $pgfile 2>/dev/null | awk '{ s+=$1 } END { if (NR > 0) printf "%d", (s/NR) }')

    # pgfile=$exp/sar_pgfaults_allflts
    # if [ ! -f $pgfile ]; then bash parse_sar.sh -n=${name} -sf=pgfaults -sc=fault/s -t1=$sample_start -t2=$sample_end -of=$pgfile; fi
    # allpgfrate=$(tail -n+2 $pgfile 2>/dev/null | awk '{ s+=$1 } END { if (NR > 0) printf "%d", s/NR }')
    # minpgfrate=$((allpgfrate-majpgfrate))

    # gather values
    HEADER="Exp";                   LINE="$name";
    HEADER="$HEADER,CPU";           LINE="$LINE,${cores}";
    HEADER="$HEADER,Threads";       LINE="$LINE,${threads}";
    HEADER="$HEADER,LocalMB";       LINE="$LINE,${localmem}";
    HEADER="$HEADER,Runtime";       LINE="$LINE,${stime}";
    HEADER="$HEADER,Xput";          LINE="$LINE,${sxput}";
    HEADER="$HEADER,RSS_KB";        LINE="$LINE,${rss}";
    HEADER="$HEADER,MajPGF";        LINE="$LINE,${pgfmajor}";
    HEADER="$HEADER,MinPGF";        LINE="$LINE,${pgfminor}";
    HEADER="$HEADER,CPU%";          LINE="$LINE,${cpuper}";
    HEADER="$HEADER,Desc";          LINE="$LINE,${desc:0:20}";    
    OUT=`echo -e "${OUT}\n${LINE}"`
done

if [[ $OUTFILE ]]; then 
    echo "${HEADER}${OUT}" > $OUTFILE
    echo "wrote results to $OUTFILE"
else
    echo "${HEADER}${OUT}" | column -s, -t -n
fi