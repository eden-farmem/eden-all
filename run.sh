#
# Run experiments
#
RUNTIME=20

# # Kona Params
# cfg=CONFIG_NO_DIRTY_TRACK
cfg=CONFIG_WP
# cfg=NO_KONA
# kona_cflags="-DPRINT_FAULT_ADDRS"
# kona_cflags="-DREGISTER_MADVISE_NOTIF"
# kona_cflags="-DBATCH_EVICTION"

EVICT_THR=.99
EVICT_DONE_THR=.99
EVICT_BATCH_SIZE=1

# # Client Params
# CONNS=1000
# MPPS=2
# KEYSPACE=10M  #not configurable yet
# MEM=1500

# # Client debugging config
CONNS=10
MPPS=1e-3
MEM=1
KEYSPACE=2K  #not configurable yet

# # Server Params
scores=4

# # Build
if [[ "$cfg" == "NO_KONA" ]]; then
    bash build.sh --shenango --memcached
else
    bash build.sh --shenango --memcached --kona -mk --kona-config=$cfg --kona-cflags=${kona_cflags}
fi

# # Run
for warmup in ""; do    #"--warmup" ""; do 
# for EVICT_DONE_THR in 0.7 0.8 0.9 0.99; do
# for EVICT_THR in 0.9; do
# for EVICT_BATCH_SIZE in 2 4; do
    # for MEM in `seq 1000 200 2600`; do
    for MEM in 1; do
    # for scores in 1 2 4 6 8 10; do
    # for scores in 4; do
        echo "Syncing clocks"
        ssh sc40 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
        ssh sc07 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"

        DESC="(debugging core dump)"
        kona_evict="--konaet ${EVICT_THR} --konaedt ${EVICT_DONE_THR} --konaebs ${EVICT_BATCH_SIZE}"
        STOPAT="--stopat 4"     # debugging
        if [[ "$cfg" == "NO_KONA" ]]; then
            python scripts/experiment.py --nokona -p udp -nc $CONNS --time $RUNTIME \
                --start $MPPS --finish $MPPS --scores $scores ${warmup} ${STOPAT} ${kona_evict} \
                -d "$KEYSPACE keys; No Kona; $DESC"
        else
            python scripts/experiment.py -km ${MEM}000000 -p udp -nc $CONNS --time $RUNTIME \
                --start $MPPS --finish $MPPS --scores $scores ${warmup} ${STOPAT} ${kona_evict} \
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