
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

# # # Vary no of tcp connections
# for conns in 200 600 1000 1400 2000; do
#     for mpps in `seq 1 0.5 6`; do
#         python experiment.py --nokona -p tcp -nc $conns --start $mpps --finish $mpps \
#             -d "no kona; 10M keys; tcp; ${conns} conns; $mpps Mpps offered; 18 scores; 18 ccores"
#         sleep 5
#     done
# done

# # Vary kona memory
conns=1000
mpps=2.0
mem=1500
scores=4

# bash build.sh -s -m 
# echo "Syncing clocks"
# ssh sc40 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
# ssh sc07 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
# python experiment.py --nokona -p udp -nc $conns --start $mpps --finish $mpps \
#     -d "no kona; 10M keys; udp; $mpps Mpps offered; 12 scores; 12 ccores; with lat&stats"
# sleep 5

bash build.sh -m -s -k -mk
# for mem in `seq 1000 200 2600`; do
for scores in 2 4 6 8 10 12; do
    echo "Syncing clocks"
    ssh sc40 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"
    ssh sc07 "sudo systemctl stop ntp; sudo ntpd -gq; sudo systemctl start ntp;"

    python experiment.py -km ${mem}000000 -p udp -nc $conns --start $mpps --finish $mpps --scores $scores \
        -d "with kona ${mem} MB; 10M keys; udp; $mpps Mpps; $scores scores; PBMEM=CONFIG_NODIRTYTRACK"
    sleep 5
done


# for mem in `seq 1000 100 2000`; do
#     python experiment.py -km ${mem}000000 -p tcp -nc $conns --start $mpps --finish $mpps \
#         -d "with kona ${mem} MB; 10M keys; tcp; ${conns} conns; $mpps Mpps offered; 12 scores, 18 ccores"
#     sleep 5
# done
