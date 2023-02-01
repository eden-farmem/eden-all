import argparse
from enum import Enum
import os
import sys
import subprocess
import pandas as pd
import numpy as np

def main():
    parser = argparse.ArgumentParser("Parse trace files and generate a heatmap")
    parser.add_argument('-i', '--input', action='store', nargs='+', help="path to the input trace file(s)", required=True)
    parser.add_argument('-p', '--ptile', action='store', type=int, choices=range(0,101), help="take top x% of locations", default=100)
    parser.add_argument('-r', '--reverse', action='store_true', help="save the file data (columns) in reverse order")
    parser.add_argument('-o', '--out', action='store', help="path to the output file")
    args = parser.parse_args()

    # read in
    origdfs=[]
    dfs = []
    for file in args.input:
        if not os.path.exists(file):
            print("can't locate input file: {}".format(file))
            exit(1)

        sys.stderr.write("reading from {}\n".format(file))
        tempdf = pd.read_csv(file, skipinitialspace=True)
        sys.stderr.write("rows read: {}\n".format(file, len(tempdf)))

        # aggregate
        tempdf = tempdf[tempdf["type"] != "zero"]
        tempdf['ip'] = tempdf['ips'].apply(lambda x: x.split('|')[2])
        tempdf = (tempdf.groupby(['ip'], as_index=False).agg(fcount=('count', 'sum'), trcount=('count', 'count')))
        tempdf = tempdf.sort_values("fcount", ascending=False)
        origdfs.append(tempdf)

        # apply %-ile
        if args.ptile and not tempdf.empty:
            tempdf['fcount_cumsum'] = tempdf['fcount'].cumsum()
            tempdf['fcount_cdf'] = tempdf['fcount_cumsum'] / tempdf['fcount_cumsum'].iloc[-1]
            ptile = tempdf['fcount_cdf'].searchsorted(args.ptile/100, side='left')
            fcountptile = tempdf['fcount'].iloc[ptile] if not tempdf.empty else 0
            tempdf = tempdf[tempdf['fcount'] >= fcountptile]
        dfs.append(tempdf)

    # find all unique traces
    allleaves = pd.concat(dfs).drop_duplicates(['ip'])

    # generate heatmap
    heatmap=np.zeros((len(allleaves), len(dfs)))

    # calculate percentage of faults each ip covers in each file
    percentmap = {}
    for i, df in enumerate(origdfs):
        fcount = df['fcount'].sum()
        for ip in allleaves['ip'].values:
            if ip not in percentmap:
                percentmap[ip] = {}
            percentmap[ip][i] = df[df['ip'] == ip]['fcount'].sum() * 100 / fcount if fcount else 0
    
    # sort by total percentages
    sumpercent = {ip: sum(percentmap[ip].values()) for ip in percentmap}
    leavesidx={ip: i for i,ip in enumerate(sorted(sumpercent, key=sumpercent.get, reverse=True))}

    # arrange in sorted order
    for ip in percentmap:
        for i, _ in enumerate(dfs):
            heatmap[leavesidx[ip]][i] = percentmap[ip][i]

    # reverse columns
    if args.reverse:
        heatmap = np.flip(heatmap, axis=1)
    
    # write heatmap to file
    sys.stderr.write("writing to {}\n".format(args.out))
    np.savetxt(args.out if args.out else sys.stdout, heatmap, delimiter=",")

if __name__ == '__main__':
    processed = 0
    main()
