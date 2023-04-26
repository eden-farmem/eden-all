#!/bin/bash
set -e

#
# Generate Fault Flame Graph for an experiment with fault samples
#

PLOTEXT=pdf
SCRIPT_PATH=`realpath $0`
SCRIPTDIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPTDIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
DATADIR=${SCRIPTDIR}/data

usage="\n
-f, --force \t\t force parse and merge raw data again\n
-rm, --remove \t\t remove the samples data if everything goes well\n
-r, --run \t\t run id, picks the latest run by default\n"

for i in "$@"
do
case $i in
    -f|--force)
    FORCE=1
    ;;

    -r=*|--run=*)
    RUNID="${i#*=}"
    ;;

    -rm|--remove)
    REMOVE=1
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

## saved run ids
# data/run-04-14-14-55-32   # full run

# take the latest run if not specified
if [ -z "${RUNID}" ]; then
    RUNID=`ls -1 ${DATADIR} | grep "run-" | sort | tail -1`
fi
expdir=${DATADIR}/${RUNID}

## merge traces
mkdir -p ${expdir}/traces
tracesfolded=${expdir}/traces/000_000.txt

if [ ! -f ${tracesfolded} ] || [[ $FORCE ]]; then
    # locate fault samples data
    allfaultsin=$(ls ${expdir}/fault-samples-*.out 2>/dev/null)
    if ! [[ $allfaultsin ]] || [ ! -f ${allfaultsin} ]; then 
        echo "no fault-samples-*.out found at ${expdir}; did you enable FAULT_SAMPLER?"
        exit 1
    fi

    #locate procmaps file (note: this is needed to resolve addresses to symbols)
    procmapflag=
    procmaps=$(ls ${expdir}/procmaps-* 2>/dev/null | head -1)
    if [ -f ${procmaps} ]; then 
        procmapflag="-pm ${procmaps}"
    fi

    echo "Merging traces..."
    if [ -f ${expdir}/run_start ]; then  stopt="-st $(cat ${expdir}/run_start)"; fi
    if [ -f ${expdir}/run_end ]; then  etopt="-et $(cat ${expdir}/run_end)"; fi
    echo "python3 ${ROOT_SCRIPTS_DIR}/parse_fltrace_samples.py -i ${allfaultsin} ${procmapflag} ${stopt} ${etopt} > ${tracesfolded}"
    python3 ${ROOT_SCRIPTS_DIR}/parse_fltrace_samples.py -i ${allfaultsin} ${procmapflag} ${stopt} ${etopt} > ${tracesfolded}
fi

srcdir=${SCRIPTDIR}/dataframe
# srcdir=${SCRIPTDIR}/dataframe/app
# LOCALIZE="-s ${srcdir} --local"

# Make flame graph
if [ ! -d ${FLAMEGRAPHDIR} ]; then 
    echo "Clone and update FLAMEGRAPHDIR to point to https://github.com/brendangregg/FlameGraph"
fi
python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${SCRIPTDIR} -i ${tracesfolded} ${LOCALIZE} --nolib -o ${expdir}/flamegraph.dat
python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${SCRIPTDIR} -i ${tracesfolded} ${LOCALIZE} --nolib -z -o ${expdir}/flamegraph-zero.dat
python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${SCRIPTDIR} -i ${tracesfolded} ${LOCALIZE} --nolib -nz -o ${expdir}/flamegraph-nonzero.dat
${ROOT_SCRIPTS_DIR}/flamegraph.pl ${expdir}/flamegraph.dat --color=fault --width=1600 --fontsize=12 > ${expdir}/flamegraph.svg
${ROOT_SCRIPTS_DIR}/flamegraph.pl ${expdir}/flamegraph-zero.dat --title "${APPNAME} (Allocation Faults)" --color=fault --width=1600 --fontsize=12 > ${expdir}/flamegraph-zero.svg
${ROOT_SCRIPTS_DIR}/flamegraph.pl ${expdir}/flamegraph-nonzero.dat --color=fault --width=1600 --fontsize=12 > ${expdir}/flamegraph-nonzero.svg

# Also dump locations in plain 
for zeroopt in "" "--zero" "--nonzero"; do
    for localopt in "" "--local"; do
        echo "OPTS: ${zeroopt} ${localopt}"
        python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${srcdir} -i ${tracesfolded} --plain ${zeroopt} ${localopt} -o ${expdir}/locations${zeroopt}${localopt}.dat
    done
done

# remove samples data
if [ ! -z "${REMOVE}" ]; then
    rm -f ${allfaultsin}
fi