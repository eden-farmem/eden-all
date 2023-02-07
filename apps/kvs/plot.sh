#!/bin/bash
set -e

#
# Gather & plot fault code locations
#

SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
PLOTDIR="${SCRIPT_DIR}/plots"
ROOTDIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
TOOL_DIR="${ROOTDIR}/fault-analysis/"
TMP_FILE_PFX="tmp_kvs_plot_"
PLOTEXT=png

source ${ROOT_SCRIPTS_DIR}/utils.sh

usage="\n
-f, --force \t\t force re-summarize data and re-generate plots\n
-fp, --force-plots \t force re-generate just the plots\n
-id, --plotid \t pick one of the many charts this script can generate\n
-a, --app \t\t pick one of the many apps this script can generate\n
-h, --help \t\t this usage information message\n"

for i in "$@"
do
case $i in
    -f|--force)
    FORCE=1
    FORCE_PLOTS=1
    ;;
    
    -fp|--force-plots)
    FORCE_PLOTS=1
    ;;

    -id=*|--fig=*|--plotid=*)
    PLOTID="${i#*=}"
    ;;

    -a=*|--app=*)
    APP="${i#*=}"
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# point to last chart if not provided
if [ -z "$PLOTID" ]; then 
    PLOTID=`grep '"$PLOTID" == "."' $0 | wc -l`
    PLOTID=$((PLOTID-1))
fi

mkdir -p $PLOTDIR

## apps
APPS='rocksdb
leveldb
redis
memcached'

# Experiments
pattern="01-2[2345]"; desc="fulltrace";

# fault locations produced by analysis tool
if [ "$PLOTID" == "1" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    plots=

    ONLYZERO="-z"
    for app in `echo ${APPS}`; do
        echo $app
        appdir=${SCRIPT_DIR}/${app}

        for cutoff in 100 95; do
            result=${plotdir}/data_${app}_${cutoff}${ONLYZERO}.csv
            if [ ! -f ${result} ] || [[ $FORCE ]]; then
                # gather runs
                pushd ${appdir}
                runinfo=${SCRIPT_DIR}/${TMP_FILE_PFX}runs
                if [[ $input ]]; then inputflag="-i=$input"; fi
                bash show.sh ${pattern} ${inputflag} -d=${desc} -of=${runinfo}
                cat ${runinfo}
                popd

                echo "name,percent,loc,floc,local,app,lmemp" > $result
                for exp in $(csv_column "$runinfo" "Exp"); do
                    echo $exp
                    expdir=${appdir}/data/$exp
                    localmem=$(cat $expdir/settings | grep "localmem:" | awk -F: '{ printf $2/1000000 }')
                    localmemp=$(cat $expdir/settings | grep "localmempercent:" | awk -F: '{ printf $2 }')

                    if [ ! -f ${expdir}/traces/000_000.txt ]; then
                        continue
                    fi

                    output=$(python3 ${TOOL_DIR}/analysis/trace_codebase.py -d ${expdir}/traces/ -r -n ${app}_${cutoff} -c ${cutoff} ${ONLYZERO})
                    echo "${output}${app},${localmemp}" >> $result
                done
            fi
        done
        # plots="${plots} -d=${plotdir}/data_${app}_100${ONLYZERO}.csv -ls solid -l ${app} -li 2 -cmi 0"
        # plots="${plots} -d=${plotdir}/data_${app}_95${ONLYZERO}.csv -ls dashed -cmi 1"
        plots="${plots} -d=${plotdir}/data_${app}_95${ONLYZERO}.csv -ls dashed -l ${app} -cmi 1"
    done

    ZOOMED="-zoomed"; YLIMS="--ymin 0 --ymax 40"
    plotname=${plotdir}/flocations${ONLYZERO}${ZOOMED}.png
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python3 ${ROOT_SCRIPTS_DIR}/plot.py ${plots}        \
            -yc "floc" -yl "Faulting Locations" ${YLIMS}    \
            -xc lmemp -xl "Local Memory (%)"                \
            --size 7 5 -fs 11 -of $PLOTEXT -o $plotname 
    fi
    display $plotname &
fi

# # unique traces
# if [ "$PLOTID" == "2" ]; then
#     plotdir=$PLOTDIR/$PLOTID
#     mkdir -p $plotdir
#     files=
#     percent=100

#     for app in `echo ${APPS}`; do
#         echo $app
#         appdir=${SCRIPT_DIR}/${app}

#         plots=
#         datafile=${plotdir}/data_${app}.csv
#         if [ ! -f ${datafile} ] || [[ $FORCE ]]; then
#             # gather data
#             pushd ${appdir}
#             if [[ $input ]]; then inputflag="-i=$input"; fi
#             bash show.sh ${pattern} ${inputflag} -d=${desc} -of=${datafile}
#             cat ${datafile}
#             popd
#         fi

#         # calculate unique traces
#         tracestats=${plotdir}/tracestats_${percent}p_${app}.csv
#         if [ ! -f ${tracestats} ]; then
#             exps="$(csv_column "$datafile" "Exp" | awk '{ print "data/"$1"/traces/000_000.txt" }')"
#             labels="$(csv_column "$datafile" "LocalMem(%)")"
#             python3 ${ROOT_SCRIPTS_DIR}/find_common_traces.py -i ${exps} -l ${labels} -p ${percent} -o ${tracestats}
#         fi
#         cat $tracestats

#         metric="leaves";    YLABEL="Faulting-Locations";
#         # metric="faults";    YLABEL="Fault-Coverage";
#         plotname=${plotdir}/${metric}_stats_${percent}p_${app}.png
#         if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
#             python3 ${ROOT_SCRIPTS_DIR}/plot.py -d ${tracestats}        \
#                 -yc "${metric}" -l "All"                                \
#                 -yc "common${metric}_all" -l "Common (A)"               \
#                 -yc "common${metric}_left" -l "Common (L)"              \
#                 -yc "common${metric}_right" -l "Common (R)"             \
#                 -yc "totalleaves" -l " "                                \
#                 -xc "label" -xl "Local Memory (%)" -yl "${YLABEL}"      \
#                 --size 3.5 2.5 -fs 9 -of $PLOTEXT -o $plotname -lt "${app}"
#         fi
#         files="${files} ${plotname}"
#     done

#     # combine
#     plotname=${plotdir}/${metric}_${percent}p_stats_all.png
#     montage -tile 3x0 -geometry +5+5 -border 5 $files ${plotname}
#     display ${plotname} &
# fi

# scatter plots for exact ips
if [ "$PLOTID" == "3" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    files=
    percent=95

    for app in `echo ${APPS}`; do
        echo $app
        appdir=${SCRIPT_DIR}/${app}

        plots=
        datafile=${plotdir}/data_${app}.csv
        if [ ! -f ${datafile} ] || [[ $FORCE ]]; then
            # gather data
            pushd ${appdir}
            if [[ $input ]]; then inputflag="-i=$input"; fi
            bash show.sh ${pattern} ${inputflag} -d=${desc} -of=${datafile}
            cat ${datafile}
            popd
        fi

        # calculate unique traces
        traces=${plotdir}/traces_${percent}p_${app}.csv
        exps="$(csv_column "$datafile" "Exp" | awk '{ print "'${app}'/data/"$1"/traces/000_000.txt" }')"
        labels="$(csv_column "$datafile" "LocalMem(%)")"
        if [ ! -f ${traces} ]; then
            python3 ${ROOT_SCRIPTS_DIR}/find_common_traces.py -i ${exps} -l ${labels}   \
                -p ${percent} --writeleaves -o ${traces}
        fi
        cat $traces

        ycols=$(head -1 ${traces} | cut -d, -f2- |  awk -F, '{ for (i=1;i<=NF;i++) printf("-yc %s ",$i); }')
        plotname=${plotdir}/traces_${percent}p_${app}.png
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            python3 ${ROOT_SCRIPTS_DIR}/plot.py -d ${traces} -z line ${ycols}   \
                -xc "xcol" -xl "Local Memory (%)" -yl "Locations"                   \
                --size 3.5 2.5 -fs 9 -of $PLOTEXT -o $plotname -lt "${app}"
        fi
        files="${files} ${plotname}"
    done

    # combine
    plotname=${plotdir}/traces_${percent}p_all.png
    montage -tile 2x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi

# time-series plots for the faults
if [ "$PLOTID" == "4" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    files=
    percent=100

    for app in `echo ${APPS}`; do
        echo $app
        appdir=${SCRIPT_DIR}/${app}

        plots=
        datafile=${plotdir}/data_${app}.csv
        if [ ! -f ${datafile} ] || [[ $FORCE ]]; then
            # gather runs
            pushd ${appdir}
            bash show.sh ${pattern} -d=${desc} -of=${datafile}
            cat ${datafile}
            popd
        fi

        # gather time series data
        for exp in $(csv_column "$datafile" "Exp"); do
            cat ${datafile} | grep "\(Exp\|${exp}\)" > ${TMP_FILE_PFX}lmemp
            lmemp=$(csv_column "${TMP_FILE_PFX}lmemp" "LocalMem(%)")
            if [ "$lmemp" == "5" ] || [ "$lmemp" == "25" ] || [ "$lmemp" == "50" ] || [ "$lmemp" == "90" ]; then
            # if [ "$lmemp" == "25" ] || [ "$lmemp" == "50" ] || [ "$lmemp" == "90" ]; then
                statsfile=${app}/data/${exp}/fltrace_parsed
                plots="${plots} -d ${statsfile} -l $lmemp"
            fi
        done
        echo $plots

        plotname=${plotdir}/tseries_${app}.png
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            python3 ${ROOT_SCRIPTS_DIR}/plot.py ${plots} -nm    \
                -xl "Time(s)" -yc faults -yl "Faults Per Sec"   \
                --size 5 2.5 -fs 9 -of $PLOTEXT -o $plotname -lt "${app}"
        fi
        files="${files} ${plotname}"
    done

    # combine
    plotname=${plotdir}/traces_${percent}p_all.png
    montage -tile 2x0 -geometry +5+5 -border 5 $files ${plotname}
    display ${plotname} &
fi

# heatmpa plots for exact ips
if [ "$PLOTID" == "5" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    files=
    percent=95

    for app in `echo ${APPS}`; do
        echo $app
        appdir=${SCRIPT_DIR}/${app}

        plots=
        datafile=${plotdir}/data_${app}.csv
        if [ ! -f ${datafile} ] || [[ $FORCE ]]; then
            # gather runs
            pushd ${appdir}
            bash show.sh ${pattern} -d=${desc} -of=${datafile}
            cat ${datafile}
            popd
        fi

        # add colorbar on the last app
        if [ "$app" == "mcached" ]; then
            colorbar="--colorbar"
        fi

        # calculate unique traces
        heatmap=${plotdir}/heatmap_${percent}p_${app}.png
        heatmap_data=${plotdir}/heatmap_${app}_${percent}.txt
        exps="$(csv_column "$datafile" "Exp" | awk '{ print "'${app}'/data/"$1"/traces/000_000.txt" }')"
        labels="$(csv_column "$datafile" "LocalMem(%)")"
        if [ ! -f ${heatmap} ] || [[ $FORCE_PLOTS ]] ; then
            # python3 ${ROOT_SCRIPTS_DIR}/find_common_traces.py -i ${exps} -l ${labels}   \
            #     -p ${percent} --heatmap -n ${app} -o ${heatmap}
            echo "python3 ${ROOT_SCRIPTS_DIR}/prepare_heatmap.py -i ${exps} -r   \
                -p ${percent} -o ${heatmap_data}"
        fi
        files="${files} ${heatmap}"
        # display ${heatmap} &
    done
    # exit

    # combine
    # plotname=${plotdir}/heatmap_${percent}p_all.png
    # montage -tile 4x0 -geometry +3+3 -border 5 $files ${plotname}
    # display ${plotname} &
fi

# fault statistics for each app
if [ "$PLOTID" == "6" ]; then
    plotdir=$PLOTDIR/$PLOTID
    mkdir -p $plotdir
    files=
    percent=100
    FRATECUTOFF=

    for app in `echo ${APPS}`; do
        if [[ $APP ]] && [[ $APP != $app ]]; then continue; fi
        echo $app
        appdir=${SCRIPT_DIR}/${app}
        TMP_FILE_PFX=${TMP_FILE_PFX}${app}_
        plots=

        datafile=${plotdir}/data_${app}.csv
        if [ ! -f ${datafile} ] || [[ $FORCE ]]; then
            # gather runs
            pushd ${appdir}
            bash show.sh ${pattern} -d=${desc} -of=${datafile}
            cat ${datafile}
            popd
        fi

        result=${plotdir}/${app}.csv
        if [ ! -f ${result} ] || [[ $FORCE ]]; then
            exps=$(csv_column "$datafile" "Exp")
            lmemp=$(csv_column "$datafile" "LocalMem(%)")
            faults=$(csv_column "$datafile" "FaultsNoZP")
            echo -e "Exp\n$exps" > ${TMP_FILE_PFX}col_exps
            echo -e "LMem(%)\n$lmemp" > ${TMP_FILE_PFX}col_lmemp
            echo -e "Faults\n$faults" > ${TMP_FILE_PFX}col_faults
            echo "FLOC" > ${TMP_FILE_PFX}col_floc
            echo "FLOC95" > ${TMP_FILE_PFX}col_floc95
            echo "FAddrs" > ${TMP_FILE_PFX}col_faddrs

            # gather more stats for each exp
            times=1
            for exp in $(csv_column "$datafile" "Exp"); do
                echo "Processing $exp"
                expdir=${appdir}/data/${exp}

                # get 100% and 95% locations
                if [ -f ${expdir}/traces${FRATECUTOFF}/000_000.txt ]; then
                    # bash ${TOOL_DIR}/analysis/clean_trace.sh ${expdir}/traces${FRATECUTOFF}/000_000.txt
                    output=$(python3 ${TOOL_DIR}/analysis/trace_codebase.py -n ${app} -d ${expdir}/traces${FRATECUTOFF}/ -c 95 -r -z)
                    floc95=$(echo $output | awk -F, '{ print $4 }')
                    echo $floc95 >> ${TMP_FILE_PFX}col_floc95
                    output=$(python3 ${TOOL_DIR}/analysis/trace_codebase.py -n ${app} -d ${expdir}/traces${FRATECUTOFF}/ -c 100 -r -z)
                    floc=$(echo $output | awk -F, '{ print $4 }')
                    echo $floc >> ${TMP_FILE_PFX}col_floc
                fi

                # get unique faulting addrs (FIXME: this is not correct)
                allfaultsin=$(ls ${expdir}/fault-samples-*.out)
                naddrs=$(python3 ${ROOT_SCRIPTS_DIR}/parse_fltrace_samples.py -i ${allfaultsin} --maxaddrs)
                echo $naddrs >> ${TMP_FILE_PFX}col_faddrs
            done

            paste -d, ${TMP_FILE_PFX}col_exps ${TMP_FILE_PFX}col_lmemp  \
                ${TMP_FILE_PFX}col_faults ${TMP_FILE_PFX}col_floc   \
                ${TMP_FILE_PFX}col_floc95 ${TMP_FILE_PFX}col_faddrs > ${result}
        fi
        cat ${result}
    done
fi

# cloc for each app
if [ "$PLOTID" == "7" ]; then
    echo "App,LOC"
    for app in `echo ${APPS}`; do
        tloc=0
        srcdir=${SCRIPT_DIR}/${app}/${app}/
        for f in `find ${srcdir}/ -name '*.c' -o -name '*.h' -o -name '*.cpp' \
                -o -name '*.hpp' -o -name '*.cxx' -o -name '*.hxx'`; do
            loc=$(cat $f | wc -l)
            tloc=$((tloc+loc))
        done
        echo $app,$tloc
    done
fi

# cleanup
rm -f ${TMP_FILE_PFX}*
