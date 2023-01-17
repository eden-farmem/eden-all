import argparse
from enum import Enum
import os
import sys
import subprocess
import pandas as pd

TIMECOL = "tstamp"
KINDCOL = "kind"

class FaultKind(Enum):
    READ = "read"
    WRITE = "write"
    WRPROTECT = "wrprotect"
    def __str__(self):
        return self.value

def kind_to_enum(kind):
    if kind == 0:   return FaultKind.READ
    if kind == 1:   return FaultKind.WRITE
    if kind == 3:   return FaultKind.WRPROTECT
    raise Exception("unknown kind: {}".format(kind))


def main():
    parser = argparse.ArgumentParser("Process input and write csv-formatted data to stdout/output file")
    parser.add_argument('-i', '--input', action='store', help="path to the input/data file", required=True)
    parser.add_argument('-st', '--start', action='store', type=int,  help='start tstamp to filter data')
    parser.add_argument('-et', '--end', action='store', type=int, help='end tstamp to filter data')
    parser.add_argument('-fk', '--kind', action='store', type=FaultKind, choices=list(FaultKind), help='filter for a specific kind of fault')
    parser.add_argument('-b', '--binary', action='store', help='path to the binary file to locate code location')
    parser.add_argument('-o', '--out', action='store', help="path to the output file")
    args = parser.parse_args()

    if not os.path.exists(args.input): 
        print("can't locate input file: {}".format(args.input))
        exit(1)

    df = pd.read_csv(args.input, skipinitialspace=True)
    sys.stderr.write("total rows read: {}\n".format(len(df)))

    # filter
    if args.start:  
        df = df[df[TIMECOL] >= args.start]
    if args.end:    
        df = df[df[TIMECOL] <= args.end]

    # rewrite and filter by kind
    df["kind"] = df.apply(lambda r: kind_to_enum(r["kind"]).value, axis=1)
    if args.kind is not None:
        df = df[df[KINDCOL] == args.kind.value]

    # group by ip or trace
    if 'trace' in df:
        df = df.groupby(['trace', 'kind']).size().reset_index(name='count')
        df = df.rename(columns={"trace": "ips"})
    else:
        df = df.groupby(['ip', 'kind']).size().reset_index(name='count')
        df = df.rename(columns={"ip": "ips"})

    df = df.sort_values("count", ascending=False)
    df["percent"] = (df['count'] / df['count'].sum()) * 100
    df["percent"] = df["percent"].astype(int)

    if args.binary:
        assert os.path.exists(args.binary)
        def addr2line(ips):
            global processed
            iplist = ips.split("|")
            code = ""
            if iplist:
                code = subprocess   \
                    .check_output(['addr2line', '-e', args.binary] + iplist) \
                    .decode('utf-8') \
                    .split("\n")
                code = "<//>".join(code)
            processed += 1
            if processed % 100 == 0:
                sys.stderr.write("processed {} entries\n".format(processed))
            return code

        sys.stderr.write("getting backtraces for {} ips\n".format(len(df)))
        df['code'] = df['ips'].apply(addr2line)

    # write out
    out = args.out if args.out else sys.stdout
    df.to_csv(out, index=False, header=True)

if __name__ == '__main__':
    processed = 0
    main()
