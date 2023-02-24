import argparse
from enum import Enum
import os
import sys
import subprocess
import pandas as pd

TIMECOL = "tstamp"

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

    if args.binary:
        assert os.path.exists(args.binary)

        # get all unique ips
        iplists = df['ips'].str.split("|")
        ips = set(sum(iplists, []))
        ips.discard("")

        # get code locations
        sys.stderr.write("getting code locations for {} ips\n".format(len(ips)))
        codemap = {}
        code = subprocess   \
            .check_output(['addr2line', '-e', args.binary] + list(ips)) \
            .decode('utf-8') \
            .split("\n")
        codemap = dict(zip(ips, code))
        # print(codemap)

        # lookup code locations
        def codelookup(ips):
            iplist = ips.split("|")
            code = "<//>".join([codemap[ip] for ip in iplist if ip in codemap])
            return code
        df['code'] = df['ips'].apply(codelookup)
    else:
        df['code'] = ""

    # write out
    out = args.out if args.out else sys.stdout
    df.to_csv(out, index=False, header=True)

if __name__ == '__main__':
    processed = 0
    main()
