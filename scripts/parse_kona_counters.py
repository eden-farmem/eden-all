import os
import argparse
import pandas as pd
import sys

TIMECOL = "time"
KONA_FIELDS_ACCUMULATED = ["n_faults", "n_faults_r", "n_faults_w", "n_net_page_in",
    "n_net_page_out", "n_madvise", "n_madvise_fail", "n_rw_fault_q", "n_page_dirty",
    "n_faults_wp", "n_flush_fail", "n_evictions", "n_afaults_r", "n_afaults_w", 
    "n_afaults"]                            
KONA_DISPLAY_FIELDS = KONA_FIELDS_ACCUMULATED + ["malloc_size", "mem_pressure"]

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
    df = df.filter(items=(KONA_DISPLAY_FIELDS + [ TIMECOL ]))
    if args.start:  df = df[df[TIMECOL] >= (args.start-1)]
    if args.end:    df = df[df[TIMECOL] <= args.end]

    # derived cols
    df['n_faults'] = df['n_faults_r'] + df['n_faults_w']
    if not 'n_evictions' in df:
        df['n_evictions'] = df['n_net_page_out']

    df[TIMECOL] = df[TIMECOL] - df[TIMECOL].iloc[0]
    for k in KONA_FIELDS_ACCUMULATED:
        if k in df:
            df[k] = df[k].diff()
    df = df.iloc[1:]    #drop first row

    # write out
    out = args.out if args.out else sys.stdout
    df.to_csv(out, index=False)
    

if __name__ == '__main__':
    main()
