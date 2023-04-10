# for paper

expdir=data/run-03-22-05-22-55
figdir=figs
mkdir -p ${figdir}

FLAMEGRAPHDIR=~/FlameGraph/   # Local path to https://github.com/brendangregg/FlameGraph
${FLAMEGRAPHDIR}/flamegraph.pl ${expdir}/flamegraph.dat --title=" " --color=fault --width=1200 --height=20 --fontsize=15 > ${figdir}/flamegraph.svg
${FLAMEGRAPHDIR}/flamegraph.pl ${expdir}/flamegraph-zero.dat --title=" " --color=fault  --width=1200 --height=20 --fontsize=15 > ${figdir}/flamegraph-zero.svg