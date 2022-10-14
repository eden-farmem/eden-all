#!/bin/bash
set -e

#
# Monitor traffic on mlnx dpdk ports 
# (100ms granularity)
#

GRANULARITY=1
echo "time,tx0,rx0,tx0_rdma,rx0_rdma,tx1,rx1,tx1_rdma,rx1_rdma"
while true
do
    # out1=$(ifconfig enp216s0f0)
    # out2=$(ifconfig enp216s0f1)
    # tx1=$(echo $out1 | grep -oP "TX packets (\K[0-9]*)")
    # rx1=$(echo $out1 | grep -oP "RX packets (\K[0-9]*)")
    # tx2=$(echo $out2 | grep -oP "TX packets (\K[0-9]*)")
    # rx2=$(echo $out2 | grep -oP "RX packets (\K[0-9]*)")
    out1=$(sudo ethtool -S  enp216s0f0)
    tx1=$(echo $out1 | grep -oP "tx_bytes: (\K[0-9]*)")
    rx1=$(echo $out1 | grep -oP "rx_bytes: (\K[0-9]*)")
    tx1_rdma=$(echo $out1 | grep -oP "tx_vport_rdma_unicast_bytes: (\K[0-9]*)")
    rx1_rdma=$(echo $out1 | grep -oP "rx_vport_rdma_unicast_bytes: (\K[0-9]*)")

    out2=$(sudo ethtool -S  enp216s0f1)
    tx2=$(echo $out2 | grep -oP "tx_bytes: (\K[0-9]*)")
    rx2=$(echo $out2 | grep -oP "rx_bytes: (\K[0-9]*)")
    tx2_rdma=$(echo $out2 | grep -oP "tx_vport_rdma_unicast_bytes: (\K[0-9]*)")
    rx2_rdma=$(echo $out2 | grep -oP "rx_vport_rdma_unicast_bytes: (\K[0-9]*)")

    if ! [[ $FIRST ]]; then   
        FIRST=1;
    else    
        # echo $tx1,$rx1,$tx2,$rx2
        echo $(date +%s),$((tx1-tx1b)),$((rx1-rx1b)),$((tx1_rdma-tx1b_rdma)),$((rx1_rdma-rx1b_rdma)),\
$((tx2-tx2b)),$((rx2-rx2b)),$((tx2_rdma-tx2b_rdma)),$((rx2_rdma-rx2b_rdma))
    fi
    tx1b=$tx1;   rx1b=$rx1;   tx1b_rdma=$tx1_rdma;  rx1b_rdma=$rx1_rdma;
    tx2b=$tx2;   rx2b=$rx2;   tx2b_rdma=$tx2_rdma;  rx2b_rdma=$rx2_rdma;
    sleep $GRANULARITY
done