#!/bin/bash
# set -e

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
-r, --run \t\t run id, picks the latest run by default\n
-l, --load \t\t generate graphs for loading phase\n"

for i in "$@"
do
case $i in
    -f|--force)
    FORCE=1
    ;;

    -r=*|--run=*)
    RUNID="${i#*=}"
    ;;

    -l|--load)
    PRELOAD="${i#*=}"
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

## saved runs
#run-04-05-19-08-05

# take the latest run if not specified
if [ -z "${RUNID}" ]; then
    RUNID=`ls -1 ${DATADIR} | grep "run-" | sort | tail -1`
fi
expdir=${DATADIR}/${RUNID}

## merge traces
mkdir -p ${expdir}/traces
tracesfolded=${expdir}/traces/000_000.txt

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

if [[ $PRELOAD ]]; then
    if [ -f ${expdir}/preload_start ]; then  stopt="-st $(cat ${expdir}/preload_start)"; fi
    if [ -f ${expdir}/preload_end ]; then etopt="-et $(cat ${expdir}/preload_end)"; fi
else
    if [ -f ${expdir}/run_start ]; then  stopt="-st $(cat ${expdir}/run_start)"; fi
    if [ -f ${expdir}/run_end ]; then  etopt="-et $(cat ${expdir}/run_end)"; fi
fi
echo "python3 ${ROOT_SCRIPTS_DIR}/parse_fltrace_samples.py -i ${allfaultsin} ${procmapflag} ${stopt} ${etopt} > ${tracesfolded}"
python3 ${ROOT_SCRIPTS_DIR}/parse_fltrace_samples.py -i ${allfaultsin} ${procmapflag} ${stopt} ${etopt} > ${tracesfolded}

# Make flame graph
if [ ! -d ${FLAMEGRAPHDIR} ]; then 
    echo "Clone and update FLAMEGRAPHDIR to point to https://github.com/brendangregg/FlameGraph"
fi
python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${SCRIPTDIR} -i ${tracesfolded}  -o ${expdir}/flamegraph.dat
python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${SCRIPTDIR} -i ${tracesfolded}  -z -o ${expdir}/flamegraph-zero.dat
${ROOT_SCRIPTS_DIR}/flamegraph.pl ${expdir}/flamegraph.dat --color=fault --width=800 --fontsize=10 > ${expdir}/flamegraph.svg
${ROOT_SCRIPTS_DIR}/flamegraph.pl ${expdir}/flamegraph-zero.dat --title "${APPNAME} (Allocation Faults)" --color=fault --width=800 --fontsize=10 > ${expdir}/flamegraph-zero.svg

# Also dump locations in plain 
srcdir=${SCRIPTDIR}/synthetic-aifm/app
python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${srcdir} -i ${tracesfolded} --plain --local -o ${expdir}/locations.dat
python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${srcdir} -i ${tracesfolded} --plain --local -z -o ${expdir}/locations-zero.dat
python3 ${ROOT_SCRIPTS_DIR}/prepare_flame_graph.py -s ${srcdir} -i ${tracesfolded} --plain --local -nz -o ${expdir}/locations-nonzero.dat