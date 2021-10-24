#
# Run experiments
#

# Sync times on machines before the run
# Requires ntp setup with sc30 as root server
# echo "Syncing clocks"
# ssh sc40 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
# ssh sc07 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"

# # Best of UDP Xput
# conns=1000
# for mpps in `seq 1 0.5 6`; do
#     python experiment.py --nokona -p udp -nc 1000 --start $mpps --finish $mpps \
#         -d "no kona; 10M keys; udp; ${conns} conns; $mpps Mpps offered; 18 scores; 18 ccores; with lat"
#     sleep 5
# done

# # Vary no of tcp connections
# for conns in 200 600 1000 1400 2000; do
#     for mpps in `seq 1 0.5 6`; do
#         python experiment.py --nokona -p tcp -nc $conns --start $mpps --finish $mpps \
#             -d "no kona; 10M keys; tcp; ${conns} conns; $mpps Mpps offered; 18 scores; 18 ccores"
#         sleep 5
#     done
# done

# # Vary kona memoryc
# cfg=CONFIG_NO_DIRTY_TRACK
cfg=CONFIG_WP
# kona_opts="PRINT_FAULT_ADDRS=1"
conns=1000
mpps=2
# conns=10
# mpps=1e-3
mem=1500
scores=4

# bash build.sh -s -m 
# echo "Syncing clocks"
# ssh sc40 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
# ssh sc07 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
# python experiment.py --nokona -p udp -nc $conns --start $mpps --finish $mpps \
#     -d "no kona; 10M keys; udp; $mpps Mpps offered; 12 scores; 12 ccores; with lat&stats"
# sleep 5

bash build.sh --shenango --kona --memcached -mk --kona-config=$cfg --kona-opts=${kona_opts}
for warmup in ""; do    #"--warmup" ""; do 
    # for mem in `seq 1000 200 2600`; do
    # for mem in 1500; do
    # for scores in 1 2 4 6 8 10; do
    for scores in 4; do
        echo "Syncing clocks"
        ssh sc40 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
        ssh sc07 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"

        python scripts/experiment.py -km ${mem}000000 -p udp -nc $conns --start $mpps \
            --finish $mpps --scores $scores ${warmup} \
            -d "(testing) 10M keys; PBMEM=${cfg} KonaOpts=${kona_opts} with madvise notif"

        # python scripts/experiment.py -km ${mem}000000 -p udp -nc $conns --start $mpps \
        #     --finish $mpps --scores $scores ${warmup} --stopat 4 \
        #     -d "(testing) 10M keys; PBMEM=${cfg} KonaOpts=${kona_opts}"
        sleep 5
    done
done


# for mem in `seq 1000 100 2000`; do
#     python experiment.py -km ${mem}000000 -p tcp -nc $conns --start $mpps --finish $mpps \
#         -d "with kona ${mem} MB; 10M keys; tcp; ${conns} conns; $mpps Mpps offered; 12 scores, 18 ccores"
#     sleep 5
# done
