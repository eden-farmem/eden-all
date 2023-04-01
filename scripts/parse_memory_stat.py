import os
import argparse
import sys
import pandas as pd

TIMECOL = "time"
ACCUMULATED_FIELDS = ["pgfault", "pgmajfault"]
TO_MB_FIELDS = ["anon", "active_anon", "inactive_anon"]
DISPLAY_FIELDS = ACCUMULATED_FIELDS + TO_MB_FIELDS + []

def append_row(df, row):
    return pd.concat([
        df, 
        pd.DataFrame([row], columns=row.index)]
    ).reset_index(drop=True)

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

    # make df from data
    header = None
    values = []
    for line in rawdata:
        fields = [x.strip() for x in line.split(",") if len(x.strip()) > 0]
        # example format: 1668057605, anon:0,file:4096,kernel_stack:0,slab:1904640,
        # sock:0,file_mapped:0,file_dirty:0,file_writeback:0,inactive_anon:0,
        # active_anon:0,inactive_file:4096,active_file:0,unevictable:0,
        # slab_reclaimable:163840,slab_unreclaimable:1740800,pgfault:228511855,
        # pgmajfault:51237817,
        assert len(fields) == 18
        time = int(fields[0])
        if not header:
            header = ["time"] + [x.split(":")[0] for x in fields[1:]]
        values.append([time] + [int(x.split(":")[1])for x in fields[1:]])
        
    # print(header, values)
    df = pd.DataFrame(columns=header, data=values)
    # print(df)

    # filter 
    df = df.filter(items=(DISPLAY_FIELDS + [ TIMECOL ]))
    if args.start:  df = df[df[TIMECOL] >= (args.start-1)]
    if args.end:    df = df[df[TIMECOL] <= args.end]

    # derived cols
    # df[""] = df[""] + df[""]

    # conversion
    for field in TO_MB_FIELDS:
        df[field + "_mb"] = (df[field] / 1024 / 1024).astype(int)

    # accumulated cols
    if not df.empty:
        df[TIMECOL] = df[TIMECOL] - df[TIMECOL].iloc[0]
        for k in ACCUMULATED_FIELDS:
            if k in df:
                df[k] = df[k].diff()
        df = df.iloc[1:]    #drop first row

    # write out
    out = args.out if args.out else sys.stdout
    df.to_csv(out, index=False)


if __name__ == '__main__':
    main()
