#!/bin/bash
set -e

#
# Monitor traffic on mlnx dpdk ports 
# (100ms granularity)
#

FIRST=1
GRANULARITY=1
echo "tx0,rx0,tx1,rx1"
while true
do
    # out1=$(ifconfig enp216s0f0)
    # out2=$(ifconfig enp216s0f1)
    # tx1=$(echo $out1 | grep -oP "TX packets (\K[0-9]*)")
    # rx1=$(echo $out1 | grep -oP "RX packets (\K[0-9]*)")
    # tx2=$(echo $out2 | grep -oP "TX packets (\K[0-9]*)")
    # rx2=$(echo $out2 | grep -oP "RX packets (\K[0-9]*)")
    out1=$(sudo ethtool -S  enp216s0f0)
    out2=$(sudo ethtool -S  enp216s0f1)
    tx1=$(echo $out1 | grep -oP "tx[0-9]*_packets: (\K[0-9]*)"| awk '{s+=$1} END {print s}')
    rx1=$(echo $out1 | grep -oP "rx[0-9]*_packets: (\K[0-9]*)"| awk '{s+=$1} END {print s}')
    tx2=$(echo $out2 | grep -oP "tx[0-9]*_packets: (\K[0-9]*)"| awk '{s+=$1} END {print s}')
    rx2=$(echo $out2 | grep -oP "rx[0-9]*_packets: (\K[0-9]*)"| awk '{s+=$1} END {print s}')
    if [[ $FIRST ]]; then   
        FIRST=  ;
    else    
        # echo $tx1,$rx1,$tx2,$rx2
        echo $((tx1-tx1b)),$((rx1-rx1b)),$((tx2-tx2b)),$((rx2-rx2b)) 
    fi
    tx1b=$tx1;   rx1b=$rx1;   tx2b=$tx2;   rx2b=$rx2;
    sleep $GRANULARITY
done