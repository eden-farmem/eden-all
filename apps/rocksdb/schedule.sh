#!/bin/bash
set -e

# Run a set of experiments

# 1000 samples per sec
# bash trace.sh -ops=30000000 -ms=1000 -lm=1000000000 -b=all
bash trace.sh -ops=30000000 -ms=1000 -lm=1000000000 -b=readseq
bash trace.sh -ops=30000000 -ms=1000 -lm=1000000000 -b=readrandom
bash trace.sh -ops=30000000 -ms=1000 -lm=1000000000 -b=readreverse

# record all samples
# bash trace.sh -ops=30000000 -lm=1000000000 -b=all
# bash trace.sh -ops=30000000 -lm=1000000000 -b=readseq
# bash trace.sh -ops=30000000 -lm=1000000000 -b=readrandom
# bash trace.sh -ops=30000000 -lm=1000000000 -b=readreverse
