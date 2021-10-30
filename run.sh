#
# Run experiments
#

# # Kona Params
# cfg=CONFIG_NO_DIRTY_TRACK
cfg=CONFIG_WP
# cfg=NO_KONA
# kona_cflags="-DPRINT_FAULT_ADDRS"
# kona_cflags="-DREGISTER_MADVISE_NOTIF"
mem=1500
EVICT_THR=.99

# # Client Params
conns=1000
mpps=2
# conns=10
# mpps=1e-3
KEYSPACE=10M  #not configurable yet

# # Server Params
scores=4

# # Build
if [[ "$cfg" == "NO_KONA" ]]; then
    bash build.sh --shenango --memcached
else
    bash build.sh --shenango --memcached --kona -mk --kona-config=$cfg --kona-cflags=${kona_cflags}
fi

# # Run
# for warmup in ""; do    #"--warmup" ""; do 
for EVICT_THR in 0.7 0.8 0.9 0.99; do
    for mem in `seq 1000 200 2600`; do
    # for mem in 2200; do
    # for scores in 1 2 4 6 8 10; do
    # for scores in 4; do
        echo "Syncing clocks"
        ssh sc40 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
        ssh sc07 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"

        DESC="varying evict thr"
        kona_evict="--konaet ${EVICT_THR} --konaedt ${EVICT_THR}"
        # STOPAT="--stopat 4"     # debugging
        if [[ "$cfg" == "NO_KONA" ]]; then
            python scripts/experiment.py --nokona -p udp -nc $conns --start $mpps \
                --finish $mpps --scores $scores ${warmup} ${STOPAT} ${kona_evict} \
                -d "$KEYSPACE keys; No Kona; $DESC"
        else
            python scripts/experiment.py -km ${mem}000000 -p udp -nc $conns --start $mpps \
                --finish $mpps --scores $scores ${warmup} ${STOPAT} ${kona_evict} \
                -d "$KEYSPACE keys; PBMEM=${cfg} KonaFlags=${kona_cflags}; $DESC"
        fi

        sleep 5
    done
done





############# ARCHIVED #################

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

# # Vary local memory
# for mem in `seq 1000 100 2000`; do
#     python experiment.py -km ${mem}000000 -p tcp -nc $conns --start $mpps --finish $mpps \
#         -d "with kona ${mem} MB; 10M keys; tcp; ${conns} conns; $mpps Mpps offered; 12 scores, 18 ccores"
#     sleep 5
# done