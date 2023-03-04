import argparse
from enum import Enum
import os
import sys
import subprocess
import pandas as pd
import re

TIMECOL = "tstamp"

# parse /proc/<pid>/maps
MAPS_LINE_RE = re.compile(r"""
    (?P<addr_start>[0-9a-f]+)-(?P<addr_end>[0-9a-f]+)\s+  # Address
    (?P<perms>\S+)\s+                                     # Permissions
    (?P<offset>[0-9a-f]+)\s+                              # Map offset
    (?P<dev>\S+)\s+                                       # Device node
    (?P<inode>\d+)\s+                                     # Inode
    (?P<pathname>.*)\s+                                   # Pathname
""", re.VERBOSE)

# proc map record
class Record:
    addr_start: int
    addr_end: int
    perms: str
    offset: int
    dev: str
    inode: int
    pathname: str

    def parse(filename):
        records = []
        with open(filename) as fd:
            for line in fd:
                m = MAPS_LINE_RE.match(line)
                if not m:
                    print("Skipping: %s" % line)
                    continue
                addr_start, addr_end, perms, offset, dev, inode, pathname = m.groups()
                r = Record()
                r.addr_start = int(addr_start, 16)
                r.addr_end = int(addr_end, 16)
                r.offset = int(offset, 16)
                r.perms = perms
                r.dev = dev
                r.inode = inode
                r.pathname = pathname
                records.append(r)
        return records

    def find_record(records, addr):
        for r in records:
            if addr >= r.addr_start and addr < r.addr_end:
                return r
        return None

# access op that resulted in the fault
class FaultOp(Enum):
    READ = "read"
    WRITE = "write"
    WRPROTECT = "wrprotect"
    def __str__(self):
        return self.value

# fault type
class FaultType(Enum):
    REGULAR = "regular"
    ZEROPAGE = "zero"
    def __str__(self):
        return self.value

def get_fault_op(flags):
    op = flags & 0x1F
    if op == 0:   return FaultOp.READ
    if op == 1:   return FaultOp.WRITE
    if op == 3:   return FaultOp.WRPROTECT
    raise Exception("unknown op: {}".format(op))

def get_fault_type(flags):
    type = flags >> 5
    if type == 0:   return FaultType.REGULAR
    if type == 1:   return FaultType.ZEROPAGE
    raise Exception("unknown type: {}".format(type))



def main():
    parser = argparse.ArgumentParser("Process input and write csv-formatted data to stdout/output file")
    parser.add_argument('-i', '--input', action='store', nargs='+', help="path to the input/data file(s)", required=True)
    parser.add_argument('-st', '--start', action='store', type=int,  help='start tstamp to filter data')
    parser.add_argument('-et', '--end', action='store', type=int, help='end tstamp to filter data')
    parser.add_argument('-fo', '--faultop', action='store', type=FaultOp, choices=list(FaultOp), help='filter for a specific fault op')
    parser.add_argument('-fr', '--frcutoff', action='store', type=int,  help='cut off the seconds where fault rate per second is less than this')
    parser.add_argument('-b', '--binary', action='store', help='path to the binary file to locate code location')
    parser.add_argument('-pm', '--procmap', action='store', help='path to the proc maps file to locate unresolved libraries')
    parser.add_argument('-ma', '--maxaddrs', action='store_true', help='just return max uniq addrs')
    parser.add_argument('-o', '--out', action='store', help="path to the output file")
    args = parser.parse_args()

    # read in
    dfs = []
    for file in args.input:
        if not os.path.exists(file):
            print("can't locate input file: {}".format(file))
            exit(1)

        tempdf = pd.read_csv(file, skipinitialspace=True)
        sys.stderr.write("rows read from {}: {}\n".format(file, len(tempdf)))
        dfs.append(tempdf)
    df = pd.concat(dfs, ignore_index=True)

    # filter
    if args.start:
        df = df[df[TIMECOL] >= args.start]
    if args.end:
        df = df[df[TIMECOL] <= args.end]

    if args.frcutoff:
        df["timesec"] = df[TIMECOL].floordiv(1000000)
        if "pages" in df:
            frate = df.groupby("timesec")["pages"].sum().reset_index(name='rate')
        else:
            frate = df.groupby("timesec").size().reset_index(name='rate')
        frate = frate[frate["rate"] >= args.frcutoff]
        df = df[df["timesec"].isin(frate["timesec"])]

    # op col renamd to flags
    FLAGSCOL="flags"
    if "kind" in df:
            FLAGSCOL="kind"

    # group by ip or trace
    TRACECOL="ip"
    if "trace" in df:
        TRACECOL="trace"

    # return max uniq addrs if specified
    if args.maxaddrs:
        df = df[df[FLAGSCOL] < 32]  # filter out zero-page faults
        df = df.groupby("addr").size().reset_index(name='count')
        print(len(df.index))
        return

    if "pages" in df:
        df = df.groupby([TRACECOL, FLAGSCOL])["pages"].sum().reset_index(name='count')
    else:
        df = df.groupby([TRACECOL, FLAGSCOL]).size().reset_index(name='count')
    df = df.rename(columns={TRACECOL: "ips"})

    df = df.sort_values("count", ascending=False)
    df["percent"] = (df['count'] / df['count'].sum()) * 100
    df["percent"] = df["percent"].astype(int)

    # NOTE: adding more columns after grouping traces is fine

    # evaluate op and filter
    if df.empty:    df["op"] = []
    else: df["op"] = df.apply(lambda r: get_fault_op(r[FLAGSCOL]).value, axis=1)
    if args.faultop is not None:
        df = df[df["op"] == args.faultop.value]

    # evaluate fault type
    if df.empty:    df["type"] = []
    else: df["type"] = df.apply(lambda r: get_fault_type(r[FLAGSCOL]).value, axis=1)

    # get all unique ips
    iplists = df['ips'].str.split("|")
    ips = set(sum(iplists, []))
    ips.discard("")

    # if binary is available, look up code locations for the ips
    codemap = {}
    if args.binary:
        assert os.path.exists(args.binary)
        sys.stderr.write("getting code locations for {} ips\n".format(len(ips)))
        code = subprocess   \
            .check_output(['addr2line', '-p', '-i', '-e', args.binary]+list(ips)) \
            .decode('utf-8') \
            .replace("\n (inlined by) ", "<<<")   \
            .split("\n")
        code.remove("")
        assert(len(code) == len(ips))
        codemap = dict(zip(ips, code))
        # print(codemap)
    
    # make a new code column
    def codelookup(ips):
        iplist = ips.split("|")
        code = "<//>".join([codemap[ip] if ip in codemap else "??:0" for ip in iplist])
        return code
    df['code'] = df['ips'].apply(codelookup)

    # if procmap is available, look up unresolved libraries
    libmap = {}
    if args.procmap:
        assert os.path.exists(args.procmap)
        records = Record.parse(args.procmap)
        sys.stderr.write("looking up libraries for {} ips\n".format(len(ips)))
        for ip in ips:
            lib = Record.find_record(records, int(ip, 16))
            if lib:
                libmap[ip] = lib.pathname
        # print(libmap)

    # make a new lib column
    def liblookup(ips):
        iplist = ips.split("|")
        lib = "<//>".join([libmap[ip] if ip in libmap else "??" for ip in iplist])
        return lib
    df['lib'] = df['ips'].apply(liblookup)

    # write out
    out = args.out if args.out else sys.stdout
    df.to_csv(out, index=False, header=True)

if __name__ == '__main__':
    processed = 0
    main()
