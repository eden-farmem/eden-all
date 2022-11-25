#
# Parse Frontswap data
#

import os
import argparse
import sys
import pandas as pd

TIMECOL = "time"
ACCUMULATED_FIELDS = ["failed_stores", "invalidates", "loads", "succ_stores"]
PAGE_FIELDS = ["curr_pages"]
DISPLAY_FIELDS = ACCUMULATED_FIELDS + PAGE_FIELDS + []

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
        # example: 1668715730,curr_pages:2586476,failed_stores:0,invalidates:
        # 2029730130,loads:906316298,succ_stores:1998341682
        assert len(fields) == 6
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
    for field in PAGE_FIELDS:
        df[field + "_mb"] = (df[field] * 4 / 1024).astype(int)

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
