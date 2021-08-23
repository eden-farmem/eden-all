# Best of UDP Xput
conns=1000
for mpps in `seq 1 0.5 6`; do
    python experiment.py --nokona -p udp -nc 1000 --start $mpps --finish $mpps \
        -d "no kona; 10M keys; udp; ${conns} conns; $mpps Mpps offered; 18 scores; 18 ccores; with lat"
    sleep 5
done

# # # Vary no of tcp connections
# for conns in 200 600 1000 1400 2000; do
#     for mpps in `seq 1 0.5 6`; do
#         python experiment.py --nokona -p tcp -nc $conns --start $mpps --finish $mpps \
#             -d "no kona; 10M keys; tcp; ${conns} conns; $mpps Mpps offered; 18 scores; 18 ccores"
#         sleep 5
#     done
# done

# # Vary kona memory
# conns=1200
# mpps=2.0
# for mem in `seq 1000 100 2000`; do
#     python experiment.py -km ${mem}000000 -p udp -nc $conns --start $mpps --finish $mpps \
#         -d "with kona ${mem} MB; 10M keys; udp; $mpps Mpps offered; 12 scores, 18 ccores"
#     sleep 5
# done
# for mem in `seq 1000 100 2000`; do
#     python experiment.py -km ${mem}000000 -p tcp -nc $conns --start $mpps --finish $mpps \
#         -d "with kona ${mem} MB; 10M keys; tcp; ${conns} conns; $mpps Mpps offered; 12 scores, 18 ccores"
#     sleep 5
# done

--nokona -p tcp -nc 200 --start 1--finish 1 -d "no kona; 10M keys; tcp; 200 conns; 1 Mpps offered; 18 scores; 18 ccores"