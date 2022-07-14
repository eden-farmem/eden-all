import os
import sys
from collections import defaultdict
import re
import argparse

# counter
idx = 0
def next_index(): 
    global idx
    idx += 1
    return idx

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

    pattern = None
    pattern_v0 = ("(\d+).*reschedules:(\d+),sched_cycles:(\d+),program_cycles:(\d+),"
    "threads_stolen:(\d+),softirqs_stolen:(\d+),softirqs_local:(\d+),parks:(\d+),"
    "preemptions:(\d+),preemptions_stolen:(\d+),core_migrations:(\d+),rx_bytes:(\d+),"
    "rx_packets:(\d+),tx_bytes:(\d+),tx_packets:(\d+),drops:(\d+),rx_tcp_in_order:(\d+),"
    "rx_tcp_out_of_order:(\d+),rx_tcp_text_cycles:(\d+),cycles_per_us:(\d+)")
    pattern_v1 = ("(\d+).*reschedules:(\d+),sched_cycles:(\d+),program_cycles:(\d+),"
    "threads_stolen:(\d+),softirqs_stolen:(\d+),softirqs_local:(\d+),parks:(\d+),"
    "preemptions:(\d+),preemptions_stolen:(\d+),core_migrations:(\d+),rx_bytes:(\d+),"
    "rx_packets:(\d+),tx_bytes:(\d+),tx_packets:(\d+),drops:(\d+),rx_tcp_in_order:(\d+),"
    "rx_tcp_out_of_order:(\d+),rx_tcp_text_cycles:(\d+),pf_posted:(\d+),"
    "pf_returned:(\d+),pf_time_spent_mus:(\d+),pf_failed:(\d+),cycles_per_us:(\d+)")
    pattern_v2 = ("(\d+).*reschedules:(\d+),sched_cycles:(\d+),program_cycles:(\d+),"
    "threads_stolen:(\d+),softirqs_stolen:(\d+),softirqs_local:(\d+),parks:(\d+),"
    "preemptions:(\d+),preemptions_stolen:(\d+),core_migrations:(\d+),rx_bytes:(\d+),"
    "rx_packets:(\d+),tx_bytes:(\d+),tx_packets:(\d+),drops:(\d+),rx_tcp_in_order:(\d+),"
    "rx_tcp_out_of_order:(\d+),rx_tcp_text_cycles:(\d+),pf_posted:(\d+),"
    "pf_returned:(\d+),pf_service_cycles:(\d+),pf_failed:(\d+),cycles_per_us:(\d+)")
    pattern_v3 = ("(\d+).*reschedules:(\d+),sched_cycles:(\d+),sched_cycles_idle:(\d+),"
    "program_cycles:(\d+),threads_stolen:(\d+),softirqs_stolen:(\d+),softirqs_local:(\d+),"
    "parks:(\d+),preemptions:(\d+),preemptions_stolen:(\d+),core_migrations:(\d+),"
    "rx_bytes:(\d+),rx_packets:(\d+),tx_bytes:(\d+),tx_packets:(\d+),drops:(\d+),"
    "rx_tcp_in_order:(\d+),rx_tcp_out_of_order:(\d+),rx_tcp_text_cycles:(\d+),pf_posted:(\d+),"
    "pf_returned:(\d+),pf_failed:(\d+),cycles_per_us:(\d+)")
    pattern_v4 = ("(\d+).*reschedules:(\d+),sched_cycles:(\d+),sched_cycles_idle:(\d+),"
    "program_cycles:(\d+),threads_stolen:(\d+),softirqs_stolen:(\d+),softirqs_local:(\d+),"
    "parks:(\d+),preemptions:(\d+),preemptions_stolen:(\d+),core_migrations:(\d+),"
    "rx_bytes:(\d+),rx_packets:(\d+),tx_bytes:(\d+),tx_packets:(\d+),drops:(\d+),"
    "rx_tcp_in_order:(\d+),rx_tcp_out_of_order:(\d+),rx_tcp_text_cycles:(\d+),pf_posted:(\d+),"
    "pf_returned:(\d+),pf_failed:(\d+),pf_annot_hits:(\d+),cycles_per_us:(\d+)")
    pattern = None

    data = defaultdict(list)
    values_old = None
    tstamps = []
    for line in rawdata:
        for pat in [ pattern_v0, pattern_v1, pattern_v2, pattern_v3, pattern_v4 ]:
            match = re.match(pat, line)
            if match:
                pattern = pat
                break
        assert pattern, line
        values = [int(match.group(i+1)) for i in range(len(match.groups()))]
        if not values_old:
            values_old = values
            continue        #ignore first value
        diff = [x - y for x, y in zip(values, values_old)]
        values_old = values

        # found columns
        global idx
        idx = 0
        ts = int(values[0])
        reschedules = diff[next_index()]
        sched_cycles = diff[next_index()]
        sched_cycles_idle = diff[next_index()] if pattern in [pattern_v3, pattern_v4] else 0
        program_cycles = diff[next_index()]
        threads_stolen = diff[next_index()]
        softirqs_stolen = diff[next_index()]
        softirqs_local = diff[next_index()]
        parks = diff[next_index()]
        preemptions = diff[next_index()]
        preemptions_stolen = diff[next_index()]
        core_migrations = diff[next_index()]
        rx_bytes = diff[next_index()]
        rx_packets = diff[next_index()]
        tx_bytes = diff[next_index()]
        tx_packets = diff[next_index()]
        drops = diff[next_index()]
        rx_tcp_in_order = diff[next_index()]
        rx_tcp_out_of_order = diff[next_index()]
        rx_tcp_text_cycles = diff[next_index()]
        pf_posted = diff[next_index()] if pattern != pattern_v0 else 0
        pf_returned = diff[next_index()] if pattern != pattern_v0 else 0
        pf_time_us = diff[next_index()] if pattern == pattern_v1 else 0   
        pf_time_cycles = diff[next_index()] if pattern == pattern_v2 else 0
        pf_failed = diff[next_index()] if pattern != pattern_v0 else 0
        pf_annot_hits = diff[next_index()] if pattern == pattern_v4 else 0
        cycles_per_us = values[next_index()] if pattern != pattern_v0 else 0

        # derived
        if pf_time_cycles:
            pf_time_us = pf_time_cycles / cycles_per_us

        tstamps.append(ts)
        data['rescheds'].append((ts, reschedules))
        data['schedtimepct'].append((ts, sched_cycles * 100.0 / (sched_cycles + program_cycles) 
            if (sched_cycles + program_cycles) else 0))
        data['sched_idle_us'].append((ts, sched_cycles_idle / cycles_per_us if cycles_per_us else 0))
        data['sched_idle_per'].append((ts, sched_cycles_idle * 100.0 / (sched_cycles + program_cycles)
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
        data['pf_time_us'].append((ts, pf_time_us))
        data['pf_failed'].append((ts, pf_failed))
        data['pf_annot_hits'].append((ts, pf_annot_hits))

        if cycles_per_us:
            sched_time_us = int(sched_cycles / cycles_per_us)
            data['sched_time_us'].append((ts, sched_time_us))
            data['cpu_idle_time'].append((ts, sched_time_us + pf_time_us))

    # filter
    if args.start:  tstamps = filter(lambda x: x >= args.start, tstamps)
    if args.end:    tstamps = filter(lambda x: x <= args.end, tstamps)
    for k in data.keys():
        if args.start:  data[k] = filter(lambda x: x[0] >= args.start, data[k])
        if args.end:    data[k] = filter(lambda x: x[0] <= args.end, data[k])

    # write out
    f = sys.stdout
    if args.out:
        f = open(args.out, "w")
        # print("writing output stats to " + args.out)
    start = min(tstamps)
    keys = data.keys()
    f.write("time," + ",".join(keys) + "\n")    # header
    for i, time in enumerate(tstamps):
        values = [str(time - start)] + [str(data[k][i][1]) for k in keys]
        f.write(",".join(values) + "\n")

if __name__ == '__main__':
    main()
