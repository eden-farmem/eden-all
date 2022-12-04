import os
from collections import defaultdict
import argparse
import sys

def parse_int(s):
    try: 
        return int(s)
    except ValueError:
        return None

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
        rawdata = f.read()
        rawdata = rawdata.split(" Stats:")[1:]

    stats = defaultdict(list)
    tstamps = []
    for d in rawdata:
        rx_pulled = None
        for line in d.strip().splitlines():
            if "eth stats for port" in line: continue
            if "rx:" in line: continue
            dats = line.split()
            tm = int(dats[0])
            for stat_name, stat_val in zip(dats[1::2], dats[2::2]):
                if not stat_name.endswith(":") or parse_int(stat_val) is None:
                    # not an effective filter but works for now
                    continue
                stats[stat_name.replace(":", "")].append((tm, int(stat_val)))
                if stat_name == "RX_PULLED:": 
                    rx_pulled = float(stat_val)
                if stat_name == "BATCH_TOTAL:": 
                    stats['IOK_SATURATION'].append((tm, rx_pulled * 100 / float(stat_val)))
    
    # Correct timestamps: A bunch of logs may get the same timestamp 
    # due to stdout flushing at irregular intervals. Assume that the 
    # last log with a particular timestamp has the correct one and work backwards
    for data in stats.values():
        oldts = None
        for i, (ts, val) in reversed(list(enumerate(data))):
            if oldts and ts >= oldts:   
                ts = oldts - 1
            data[i] = (ts, val)
            oldts = ts

    # filter
    for k in stats.keys():
        if args.start:  stats[k] = filter(lambda x: x[0] >= args.start, stats[k])
        if args.end:    stats[k] = filter(lambda x: x[0] <= args.end, stats[k])

    # # detect anamoly
    # mean = None
    # for i, (_, val) in enumerate(stats['TX_PULLED']):
    #     if mean:
    #         if val < mean / 2.0:    print("WARNING! drastic throughput drop detected, possible soft crash")
    #         mean = (mean * i + val) / (i + 1)
    #     else:   
    #         mean = val

    # write out
    f = sys.stdout
    if args.out:
        f = open(args.out, "w")
        # print("writing output stats to " + args.out)
    tstamps = [ts for ts,_ in list(stats.values())[0]]
    if len(tstamps) > 0:
        start = min(tstamps)
        f.write("time," + ",".join(stats.keys()) + "\n")    # header
        for i, time in enumerate(tstamps):
            values = [str(time - start)] + [str(v[i][1]) for v in stats.values()]
            f.write(",".join(values) + "\n")
    
if __name__ == '__main__':
    main()
