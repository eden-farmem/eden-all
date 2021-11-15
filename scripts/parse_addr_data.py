#
# Parses userfaultfd addresses raw output data
# and cleans it for charts
#

import os
import argparse
import re
import glob
from collections import defaultdict

PAGE_OFFSET = 12
ADDR_PATTERN = "(read|write|eviction) fault at ([a-z0-9]+)"
CHECKPT_PATTERN = "Checkpoint (\S+):([0-9]+)"
CLIENT_LOG = "0-sc2-hs2-b1607.memcached.out"

def main():
    parser = argparse.ArgumentParser("Visualize mem access patterns")
    parser.add_argument('-n', '--name', action='store', help='Exp (directory) name')
    parser.add_argument('-d', '--dir', action='store', help='Path to data dir', default="./data")
    parser.add_argument('-of', '--offset', action='store_true', help='Offset addresses', default=False)
    args = parser.parse_args()
    
    expname = args.name
    if not expname:  
        subfolders = glob.glob(args.dir + "/*/")
        latest = max(subfolders, key=os.path.getctime)
        expname = os.path.basename(os.path.split(latest)[0])
    dirname = os.path.join(args.dir, expname)

    start = None
    end = None
    times = []
    addrs = []
    types = []
    with open("{}/memcached.out".format(dirname), 'r') as f:
        lines = f.read().splitlines()
        for line in lines:
            (time, log) = line.split(" ", 1)
            
            # Check for printed address
            match = re.search(ADDR_PATTERN, log)
            if not start:   start = int(time)
            if match:
                type_ = match.group(1)
                addr = int(match.group(2), 16)
                page = addr >> PAGE_OFFSET
                times.append(int(time))
                addrs.append(addr)
                types.append(type_)
                end = int(time)
            
    # Check for checkpoints
    checkpoints = {}
    with open("{}/{}".format(dirname, CLIENT_LOG), 'r') as f:
        lines = f.read().splitlines()
        for line in lines:     
            match = re.match(CHECKPT_PATTERN, line)
            if match:
                label = match.group(1)
                time = int(match.group(2))
                checkpoints[label] = time
    if "PreloadStart" in checkpoints:   start = checkpoints["PreloadStart"]

    times = [t - start for t in times]
    samples_per_sec = {t:times.count(t) for t in range(max(times))}
    if args.offset:
        min_addr = (min(addrs) >> PAGE_OFFSET) << PAGE_OFFSET
        addrs = [x - min_addr for x in addrs]

    outdir = "{}/addrs/".format(dirname)
    if not os.path.exists(outdir):
        os.makedirs(outdir)
    
    if checkpoints:
        with open(os.path.join(outdir, "checkpoints"), "w") as f:
            for pt,time in checkpoints.items():
                if start <= time <= end:
                    f.write("{},{}\n".format(pt, time-start))
    
    # Write addresses to file
    writes = os.path.join(outdir, "wfaults")
    reads = os.path.join(outdir, "rfaults")
    evicts = os.path.join(outdir, "evictions")
    header = "time,addr,page,pgofst,gap\n"
    last_write = last_read = last_evict = None
    with open(writes, "w") as wf, open(reads, "w") as rf, open(evicts, "w") as ef:
        wf.write(header);   rf.write(header);   ef.write(header)
        step = 0.0
        prev_time = -1
        for time, addr, type_ in zip(times, addrs, types):
            if time in samples_per_sec and samples_per_sec[time]: 
                step += 1.0 / samples_per_sec[time]
            if time != prev_time:   step = 0.0
            if type_ == "read":
                rf.write("{},{},{},{},{}\n".format(float(time)+step, addr, 
                    addr >> PAGE_OFFSET, addr & (1<<PAGE_OFFSET-1), 
                    addr - last_read if last_read else 0))
                last_read = addr
            elif type_ == "write":
                wf.write("{},{},{},{},{}\n".format(float(time)+step, addr, 
                    addr >> PAGE_OFFSET, addr & (1<<PAGE_OFFSET-1),
                    addr - last_read if last_read else 0))
                last_write = addr
            else:
                ef.write("{},{},{},{},{}\n".format(float(time)+step, addr, 
                    addr >> PAGE_OFFSET, addr & (1<<PAGE_OFFSET-1),
                    addr - last_evict if last_evict else 0))
                last_evict = addr
            prev_time = time

    # Count and write stats
    tidx = min(times)
    rcount = wcount = ecount = 0
    counts = []
    for t1, type_ in zip(times, types):
        if tidx < t1:
            counts.append((tidx, rcount, wcount, ecount))
            rcount = wcount = ecount = 0
            tidx += 1
            while tidx < t1:
                counts.append((tidx, 0, 0, 0))
                tidx += 1
        if tidx == t1:
            if type_ == "read":     rcount += 1
            elif type_ == "write":  wcount += 1
            else:                   ecount += 1
            continue
        assert tidx > t1, "Shouldn't be the case!"

    outfile = os.path.join(outdir, "counts")
    with open(outfile, "w") as f:
        f.write("time,rfaults,wfaults,evictions\n")
        for time, rcount, wcount, ecount in counts:
            f.write("{},{},{},{}\n".format(time, rcount, wcount, ecount))

if __name__ == '__main__':
    main()
