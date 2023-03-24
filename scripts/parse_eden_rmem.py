import os
import argparse
import sys
import pandas as pd
import numpy as np

TIMECOL = "time"
NON_CUMULATIVE_FIELDS = ["rmalloc_size", "rmunmap_size", "rmadv_size", "memory_used"]
TO_MB_FIELDS = ["rmalloc_size", "rmunmap_size", "rmadv_size", "memory_used"]

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
    header_total = None
    header_handler = None
    total = []
    handler = []
    ncols = 0
    ncols_common = 0
    for line in rawdata:
        # example format: 1668069597 total-faults:0,faults_r:0,faults_w:212251,
        # faults_wp:0,wp_upgrades:0,faults_zp:0,faults_done:212251,uffd_notif:0,
        # uffd_retries:0,rdahead_ops:0,rdahead_pages:0,
        # evict_ops:0,evict_pages:0,evict_no_candidates:0,evict_incomplete_batch:0,
        # evict_writes:0,evict_wp_retries:0,evict_madv:0,evict_ops_done:0,
        # evict_pages_done:0,net_reads:212251,net_writes:0,steals_ready:0,
        # steals_wait:0,wait_retries:0,rmalloc_size:4294967296,rmunmap_size:0,
        # rmadv_size:0,total_cycles:0,work_cycles:0,backend_wait_cycles:0,annot_hits:0
        # total faults may include extra columns at the end
        assert(line)
        time = int(line.split()[0])
        rest = line.split()[1]
        type = rest.split('-', 1)[0]
        vals = rest.split('-', 1)[1]
        fields = [x.strip() for x in vals.split(',') if len(x.strip()) > 0]
        assert type in ["total", "handler"]
        if type == "total":
            if not header_total:
                header_total = ["time"] + [x.split(":")[0] for x in fields]
            assert(len(fields) == len(header_total) - 1)
            total.append([time] + [int(x.split(":")[1]) for x in fields])
        else:
            if not header_handler:
                header_handler = ["time"] + [x.split(":")[0] for x in fields]
            assert(len(fields) == len(header_handler) - 1)
            handler.append([time] + [int(x.split(":")[1]) for x in fields])
        
    # print(header, total, handler)
    tdf = pd.DataFrame(columns=header_total, data=total)
    hdf = pd.DataFrame(columns=header_handler, data=handler)
    # print(tdf, hdf)

    # filter 
    if args.start:  
        tdf = tdf[tdf[TIMECOL] >= (args.start-1)]
        hdf = hdf[hdf[TIMECOL] >= (args.start-1)]
    if args.end:
        tdf = tdf[tdf[TIMECOL] <= args.end]
        hdf = hdf[hdf[TIMECOL] <= args.end]

    # derived cols
    tdf["steals"] = tdf["steals_ready"] + tdf["steals_wait"]
    hdf["steals"] = hdf["steals_ready"] + hdf["steals_wait"]

    # conversion
    for field in TO_MB_FIELDS:
        if field in tdf:
            tdf[field + "_mb"] = (tdf[field] / 1024 / 1024).astype(int)
        if field in hdf:
            hdf[field + "_mb"] = (hdf[field] / 1024 / 1024).astype(int)

    # accumulated cols
    if len(tdf) > 1:
        tdf[TIMECOL] = tdf[TIMECOL] - tdf[TIMECOL].iloc[0]
        for k in tdf:
            if k not in NON_CUMULATIVE_FIELDS:
                tdf[k] = tdf[k].diff()
        tdf = tdf.iloc[1:]    #drop first row
        
    if len(hdf) > 1:
        hdf[TIMECOL] = hdf[TIMECOL] - hdf[TIMECOL].iloc[0]
        for k in hdf:
            if k not in NON_CUMULATIVE_FIELDS:
                hdf[k] = hdf[k].diff()
        hdf = hdf.iloc[1:]    #drop first row

    if not tdf.empty:
        if 'total_cycles' in tdf and tdf['total_cycles'].iloc[0] > 0:
            tdf['cpu_per'] = tdf['work_cycles'] * 100 / tdf['total_cycles']
            tdf['cpu_per'] = tdf['cpu_per'].replace(np.inf, 0).astype(int)
    
    if not hdf.empty:
        if 'total_cycles' in hdf and hdf['total_cycles'].iloc[0] > 0:
            hdf['cpu_per'] = hdf['work_cycles'] * 100 / hdf['total_cycles']
            hdf['cpu_per'] = hdf['cpu_per'].replace(np.inf, 0).astype(int)

    # merge both
    df = pd.merge(tdf, hdf, on=TIMECOL, how='left', suffixes=('', '_h'))
    # print(df)

    # write out
    out = args.out if args.out else sys.stdout
    df.to_csv(out, index=False)


if __name__ == '__main__':
    main()
