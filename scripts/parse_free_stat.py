import os
import argparse
import sys
import pandas as pd

TIMECOL = "time"
COLUMNS = ["mem-total", "mem-used", "mem-free", "mem-shared", "mem-buffers",
    "mem-cache", "mem-available", "swap-total", "swap-used", "swap-free"]

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
        assert len(fields) == len(COLUMNS) + 1
        values.append([int(x)for x in fields])
        
    # print(header, values)
    df = pd.DataFrame(columns=([TIMECOL] + COLUMNS), data=values)
    # print(df)

    # filter 
    if args.start:  df = df[df[TIMECOL] >= (args.start-1)]
    if args.end:    df = df[df[TIMECOL] <= args.end]

    # derived cols
    # df[""] = df[""] + df[""]

    # conversion
    for field in COLUMNS:
        df[field + "_mb"] = (df[field] / 1024 / 1024).astype(int)

    # accumulated cols
    if not df.empty:
        df[TIMECOL] = df[TIMECOL] - df[TIMECOL].iloc[0]
        for k in COLUMNS:
            if k in df:
                df[k] = df[k].diff()
        df = df.iloc[1:]    #drop first row

    # write out
    out = args.out if args.out else sys.stdout
    df.to_csv(out, index=False)


if __name__ == '__main__':
    main()
