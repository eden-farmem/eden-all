#!/bin/bash
set -e

#Defaults
SCRIPT_DIR=`dirname "$0"`
TEMP_PFX=tmp_kona_
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=plots 
DATADIR=data
PLOTEXT=png
CFGFILE=${TEMP_PFX}shenango.config
LATFILE=latencies

# plot xput
plotname=${PLOTDIR}/fault_xput.${PLOTEXT}
python ${PLOTSRC}   \
    -d data/xput-rmem-read-1hthr -l "hthr=1"    \
    -d data/xput-rmem-read-2hthr -l "hthr=2"    \
    -d data/xput-rmem-read-4hthr -l "hthr=4"    \
    -d data/xput-hints-read-1hthr -l "hints"    \
    -xc cores -xl "App CPU"                 \
    -yc xput -yl "MOPS" --ymul 1e-6         \
    --ymin 0 --ymax 1.5                     \
    --size 4.5 3 -fs 11 -of ${PLOTEXT} -o $plotname
display $plotname &