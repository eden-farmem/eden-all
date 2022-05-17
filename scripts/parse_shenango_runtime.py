import os
import sys
from collections import defaultdict
import re
import argparse

def main():
    parser = argparse.ArgumentParser("Process input and write csv-formatted data to stdout/output file")
    parser.add_argument('-i', '--input', action='store', help="path to the input/data file", required=True)
    parser.add_argument('-st', '--start', action='store', type=int,  help='start (unix) time to filter data')
    parser.add_argument('-et', '--end', action='store', type=int, help='end (unix) time to filter data')
    parser.add_argument('-o', '--out', action='store', help="path to the output file")
    args = parser.parse_args()

    if not os.path.exists(args.input): 
        print("can't locate input file: {}".format(args.input))
        exit(1)

    with open(args.input) as f:
        rawdata = f.read().splitlines()

    pattern_old = ("(\d+).*reschedules:(\d+),sched_cycles:(\d+),program_cycles:(\d+),"
    "threads_stolen:(\d+),softirqs_stolen:(\d+),softirqs_local:(\d+),parks:(\d+),"
    "preemptions:(\d+),preemptions_stolen:(\d+),core_migrations:(\d+),rx_bytes:(\d+),"
    "rx_packets:(\d+),tx_bytes:(\d+),tx_packets:(\d+),drops:(\d+),rx_tcp_in_order:(\d+),"
    "rx_tcp_out_of_order:(\d+),rx_tcp_text_cycles:(\d+),cycles_per_us:(\d+)")
    pattern_new = ("(\d+).*reschedules:(\d+),sched_cycles:(\d+),program_cycles:(\d+),"
    "threads_stolen:(\d+),softirqs_stolen:(\d+),softirqs_local:(\d+),parks:(\d+),"
    "preemptions:(\d+),preemptions_stolen:(\d+),core_migrations:(\d+),rx_bytes:(\d+),"
    "rx_packets:(\d+),tx_bytes:(\d+),tx_packets:(\d+),drops:(\d+),rx_tcp_in_order:(\d+),"
    "rx_tcp_out_of_order:(\d+),rx_tcp_text_cycles:(\d+),pf_posted:(\d+),"
    "pf_returned:(\d+),pf_retries:(\d+),pf_failed:(\d+),cycles_per_us:(\d+)")
    pattern = None

    data = defaultdict(list)
    values_old = None
    tstamps = []
    for line in rawdata:
        match = re.match(pattern_old, line)
        if not match:   match = re.match(pattern_new, line)
        if match:
            assert len(match.groups()) == 20 or len(match.groups()) == 24
            values = [int(match.group(i+1)) for i in range(len(match.groups()))]
            if not values_old:
                values_old = values
                continue        #ignore first value
            diff = [x - y for x, y in zip(values, values_old)]
            values_old = values

            ts = int(values[0])
            reschedules = diff[1]
            sched_cycles = diff[2]
            program_cycles = diff[3]
            threads_stolen = diff[4]
            softirqs_stolen = diff[5]
            softirqs_local = diff[6]
            parks = diff[7]
            preemptions = diff[8]
            preemptions_stolen = diff[9]
            core_migrations = diff[10]
            rx_bytes = diff[11]
            rx_packets = diff[12]
            tx_bytes = diff[13]
            tx_packets = diff[14]
            drops = diff[15]
            rx_tcp_in_order = diff[16]
            rx_tcp_out_of_order = diff[17]
            rx_tcp_text_cycles = diff[18]
            cycles_per_us = values[19] 
            if len(match.groups()) == 24:
                pf_posted = diff[19]
                pf_returned = diff[20]
                pf_retries = diff[21]
                pf_failed = diff[22]
                cycles_per_us = values[23]

            # print(values)
            # print(diff)

            tstamps.append(ts)
            data['rescheds'].append((ts, reschedules))
            data['schedtimepct'].append((ts, sched_cycles / (sched_cycles + program_cycles) * 100 
                if (sched_cycles + program_cycles) else 0))
            data['localschedpct'].append((ts, (1 - threads_stolen / reschedules) * 100 if reschedules else 0))
            data['softirqs'].append((ts, softirqs_local + softirqs_stolen))
            data['stolenirqpct'].append((ts, (softirqs_stolen / (softirqs_local + softirqs_stolen)) * 100 
                if (softirqs_local + softirqs_stolen) else 0))
            data['cpupct'].append((ts, (sched_cycles + program_cycles) * 100 /(float(cycles_per_us) * 1000000)))
            data['parks'].append((ts, parks))
            data['migratedpct'].append((ts, core_migrations * 100 / parks if parks else 0))
            data['preempts'].append((ts, preemptions))
            data['stolenpct'].append((ts, preemptions_stolen))
            data['rxpkt'].append((ts, rx_packets))
            data['rxbytes'].append((ts, rx_bytes))
            data['txpkt'].append((ts, tx_packets))
            data['txbytes'].append((ts,tx_bytes ))
            data['drops'].append((ts, drops))
            data['p_rx_ooo'].append((ts, rx_tcp_out_of_order / (rx_tcp_in_order + rx_tcp_out_of_order) * 100
                if (rx_tcp_in_order + rx_tcp_out_of_order) else 0))
            data['p_reorder_time'].append((ts, rx_tcp_text_cycles / (sched_cycles + program_cycles) * 100
                if (sched_cycles + program_cycles) else 0))
            data['pf_posted'].append((ts, pf_posted))
            data['pf_returned'].append((ts, pf_returned))
            data['pf_retries'].append((ts, pf_retries))
            data['pf_failed'].append((ts, pf_retries))
            continue
        assert False, line

    # filter
    if args.start:  tstamps = filter(lambda x: x[0] >= args.start, tstamps)
    if args.end:    tstamps = filter(lambda x: x[0] <= args.end, tstamps)
    for k in data.keys():
        if args.start:  data[k] = filter(lambda x: x[0] >= args.start, data[k])
        if args.end:    data[k] = filter(lambda x: x[0] <= args.end, data[k])

    # write out
    f = sys.stdout
    if args.out:
        f = open(args.out, "w")
        print("writing output stats to " + args.out)
    start = min(tstamps)
    keys = data.keys()
    f.write("time," + ",".join(keys) + "\n")    # header
    for i, time in enumerate(tstamps):
        values = [str(time - start)] + [str(data[k][i][1]) for k in keys]
        f.write(",".join(values) + "\n")

if __name__ == '__main__':
    main()
