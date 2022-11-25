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
plotname=${PLOTDIR}/fastswap_v_eden.${PLOTEXT}
python3 ${PLOTSRC}   \
    -d data/xput-hints-noevict-local-read   -l "eden-read"      -ls dashed  -cmi 1  \
    -d data/xput-fswap-noevict-local-read   -l "fswap-read"     -ls dashed  -cmi 1  \
    -d data/xput-fswap+3-noevict-local-write  -l "fswap-write"  -ls solid   -cmi 1  \
    -xc cores -xl "App CPU"  -yc xput -yl "MOPS" --ymul 1e-6  --ymin 0 --ymax 2.5   \
    --size 5 3.5 -fs 11 -of ${PLOTEXT} -o $plotname
display $plotname &

# # plot xput
# plotname=${PLOTDIR}/fastswap_v_eden_rdahead.${PLOTEXT}
# python3 ${PLOTSRC}   \
#     -d data/xput-hints-noevict-local-read       -l "eden"      -ls dashed  -cmi 0   \
#     -d data/xput-hints+1-noevict-local-read     -l "eden+1"    -ls solid   -cmi 0   \
#     -d data/xput-hints+2-noevict-local-read     -l "eden+2"    -ls dotted  -cmi 0   \
#     -d data/xput-hints+4-noevict-local-read     -l "eden+4"    -ls dashdot -cmi 1   \
#     -d data/xput-fswap-noevict-local-read       -l "fswap"     -ls dashed  -cmi 0   \
#     -d data/xput-fswap+1-noevict-local-read     -l "fswap+1"   -ls solid   -cmi 0   \
#     -d data/xput-fswap+3-noevict-local-read     -l "fswap+3"   -ls dotted  -cmi 0   \
#     -d data/xput-fswap+7-noevict-local-read     -l "fswap+7"   -ls dashdot -cmi 1   \
#     -xc cores -xl "App CPU"  -yc xput -yl "MOPS" --ymul 1e-6  --ymin 0 --ymax 2.5   \
#     --size 5 3.5 -fs 11 -of ${PLOTEXT} -o $plotname
# display $plotname &