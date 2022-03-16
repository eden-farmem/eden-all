#
# Run experiments
#
RUNTIME=20

# # Kona Params
# KCFG=CONFIG_NO_DIRTY_TRACK
KCFG=CONFIG_WP
# KCFG=NO_KONA
# KFLAGS="-DPRINT_FAULT_ADDRS"
# KFLAGS="-DREGISTER_MADVISE_NOTIF"
# KFLAGS="-DBATCH_EVICTION"

EVICT_THR=.99
EVICT_DONE_THR=.99
EVICT_BATCH_SIZE=1

# Client Params
CONNS=100
MPPS=2           #undo
KEYSPACE=10M        #not configurable yet
MEM=1600

# Client debugging config
# CONNS=5
# MPPS=1e-2
# MEM=.5
# KEYSPACE=10K  #not configurable yet, 10MB remote mem?
# DEBUG_FLAG="--debug"

# # Server Params
SCORES=4

# # Build
set -e
if [[ "$KCFG" == "NO_KONA" ]]; then
    bash build.sh --shenango --memcached
else
    bash build.sh ${DEBUG_FLAG} --shenango --memcached --kona   \
        -wk --kona-config=$KCFG --kona-cflags=${KFLAGS} -spf=ASYNC #--gdb
fi

set +e

# # Run
# for warmup in "--warmup"; do 
# for KFLAGS in ""; do
# for KFLAGS in "" "-DREGISTER_MADVISE_NOTIF"; do
    # for EVICT_THR in 0.9; do
    # for EVICT_DONE_THR in 0.92 0.94 0.96; do
    # for EVICT_BATCH_SIZE in 2 4; do
    for SCORES in 4; do
        # for mem in `seq 1000 200 2000`; do
        for mem in $MEM; do
        # for SCORES in 1 2 4 6 8 10; do
            echo "Syncing clocks"
            ssh sc40 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
            ssh sc07 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"

            DESC="debugging silent crash; no stealing; no parks; with gdb"
            kona_evict="--konaet ${EVICT_THR} --konaedt ${EVICT_DONE_THR} --konaebs ${EVICT_BATCH_SIZE}"
            kona_mem_bytes=`echo $mem | awk '{ print $1*1000000 }'`
            STOPAT="--stopat 4"     
            # debugging
            if [[ "$KCFG" == "NO_KONA" ]]; then
                python scripts/experiment.py --nokona -p udp -nc $CONNS --time $RUNTIME             \
                    --start $MPPS --finish $MPPS --scores $SCORES ${warmup} ${STOPAT} ${kona_evict} \
                    -d "$KEYSPACE keys; No Kona; $DESC"
            else
                python scripts/experiment.py -km ${kona_mem_bytes} -p udp -nc $CONNS --time $RUNTIME    \
                    --start $MPPS --finish $MPPS --scores $SCORES ${warmup} ${STOPAT} ${kona_evict}     \
                    -d "$KEYSPACE keys; PBMEM=${KCFG} KonaFlags=${KFLAGS}; $DESC"
            fi

            sleep 5
        done
    done
# done


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