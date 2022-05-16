import os
import argparse
import pandas as pd

TIMECOL = "time"

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

    # filter 
    if args.start:  df = df[df[TIMECOL] >= args.start]
    if args.end:    df = df[df[TIMECOL] <= args.end]
    df[TIMECOL] = df[TIMECOL] - df[TIMECOL].iloc[0]

    # write out
    out = args.out if args.out else sys.stdout
    df.to_csv(out, index=False)

if __name__ == '__main__':
    main()
