import os
import argparse
import pandas as pd
import sys
import random

TIMECOL = "time"
ADDRCOL = "address"

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

    df = pd.read_csv(args.input, skipinitialspace=True)
    df[ADDRCOL] = df[ADDRCOL].apply(int, base=16)

    # filter (timecol is in micro-secs)
    if args.start:  df = df[df[TIMECOL] >= args.start * 1000000]
    if args.end:    df = df[df[TIMECOL] <= args.end * 1000000]
    # df[TIMECOL] = df[TIMECOL] - df[TIMECOL].iloc[0]
    tmp_df = df.groupby(ADDRCOL)[TIMECOL].count().reset_index(name="refaults")
    new_df = tmp_df.groupby("refaults")[ADDRCOL].count().reset_index(name="count")
    new_df["refaults"] = new_df["refaults"] - 1
    # print(new_df.head(10))

    # write out
    out = args.out if args.out else sys.stdout
    new_df.to_csv(out, index=False, header=True)

if __name__ == '__main__':
    main()
