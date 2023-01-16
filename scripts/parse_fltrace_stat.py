import os
import argparse
import sys
import pandas as pd
import numpy as np

TIMECOL = "time"
TO_MB_FIELDS = ["rmalloc_size", "rmunmap_size", "rmadv_size", 
    "memory_used", "memory_allocd", "memory_freed",
    "vm_peak", "vm_size", "vm_lock", "vm_hwm", "vm_rss", "vm_data", "vm_stk",
    "vm_exe", "vm_lib", "vm_pte", "vm_swap" ]
NON_ACCUMULATED_FIELDS = TO_MB_FIELDS + []

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
    counters = []
    for line in rawdata:
        assert(line)
        time = int(line.split()[0])
        vals = line.split()[1]
        fields = [x.strip() for x in vals.split(',') if len(x.strip()) > 0]
        # assert len(fields) == 29, "in {}".format(args.input)
        if not header:
            header = ["time"] + [x.split(":")[0] for x in fields]
        counters.append([time] + [int(x.split(":")[1]) for x in fields])

    # print(header)
    # print(counters)
        
    # print(header, total, handler)
    df = pd.DataFrame(columns=header, data=counters)
    # print(df)

    # filter 
    if args.start:  
        df = df[df[TIMECOL] >= (args.start-1)]
    if args.end:
        df = df[df[TIMECOL] <= args.end]

    # derived cols

    # accumulated cols
    if not df.empty:
        df[TIMECOL] = df[TIMECOL] - df[TIMECOL].iloc[0]
        for k in df.keys():
            if k not in NON_ACCUMULATED_FIELDS:
                df[k] = df[k].diff()
        df = df.iloc[1:]    #drop first row

    # conversion
    for field in TO_MB_FIELDS:
        if field in df:
            df[field + "_mb"] = (df[field] / 1024 / 1024).astype(int)
        
    if not df.empty:
        if 'total_cycles' in df and df['total_cycles'].iloc[0] > 0:
            df['cpu_per'] = df['work_cycles'] * 100 / df['total_cycles']
            df['cpu_per'] = df['cpu_per'].replace(np.inf, 0).astype(int)
    
    # write out
    out = args.out if args.out else sys.stdout
    df.to_csv(out, index=False)


if __name__ == '__main__':
    main()
