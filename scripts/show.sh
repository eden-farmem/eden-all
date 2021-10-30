#!/bin/bash
# set -e
#
# Show info on past (good) runs
# For previous data, activate "data" repo in git submodules (.gitmodules)
#

prefix=$1
if [ -z "$prefix" ];  then    prefix=$(date +"%m-%d");    fi    # today

HOST="sc2-hs2-b1630"
CLIENT="sc2-hs2-b1607"
OUT=`echo Exp,Kona Mem,EvThr,EvDThr,Cores,Mpps,Prot,Comments`

# for f in `ls data/run-08-20-*/config.json`; do
for f in `ls data/run-${prefix}*/config.json`; do
    # Data from config.json
    echo $f
    dir=`dirname $f`
    name=`jq '.name' $f | tr -d '"'`
    desc=`jq '.desc' $f | tr -d '"'`
    konamem=`jq '.apps."'$HOST'" | .[] | select(.name=="memcached") | .kona.mlimit' $f`
    if [ $konamem == "null" ]; then    konamem_mb="-";
    else    konamem_mb=`echo $konamem | awk '{ printf "%-4d MB", $1/1000000 }'`;     fi
    konaet=`jq '.apps."'$HOST'" | .[] | select(.name=="memcached") | .kona.evict_thr' $f`
    konaedt=`jq '.apps."'$HOST'" | .[] | select(.name=="memcached") | .kona.evict_done_thr' $f`
    sthreads=`jq '.apps."'$HOST'" | .[] | select(.name=="memcached") | .threads' $f`
    prot=`jq -r '.clients."'$CLIENT'" | .[] | select(.app=="synthetic") | .transport' $f`
    nconns=`jq '.clients."'$CLIENT'" | .[] | select(.app=="synthetic") | .client_threads' $f`
    mpps=`jq '.clients."'$CLIENT'" | .[] | select(.app=="synthetic") | .mpps' $f`
    desc=`jq '.desc' $f`

    # Print all
    LINE=`echo $name,$konamem_mb,$konaet,$konaedt,$sthreads,$mpps,$prot,$desc`
    OUT=`echo -e "${OUT}\n${LINE}"`
done

echo "$OUT" | column -s, -t