import argparse
from enum import Enum
import os
import sys
import subprocess
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

# access op that resulted in the fault 
class FaultOp(Enum):
    READ = "read"
    WRITE = "write"
    WRPROTECT = "wrprotect"
    def __str__(self):
        return self.value

# fault type
class FaultType(Enum):
    REGULAR = "regular"
    ZEROPAGE = "zero"
    def __str__(self):
        return self.value


def main():
    parser = argparse.ArgumentParser("Find and print traces specific to each trace file")
    parser.add_argument('-i', '--input', action='store', nargs='+', help="path to the input trace file(s)", required=True)
    parser.add_argument('-l', '--label', action='store', nargs='+', help="label for each input trace file(s)")
    parser.add_argument('-p', '--ptile', action='store', type=int, choices=range(0,101), help="take top x% of locations", default=100)
    parser.add_argument('-wl', '--writeleaves', action='store_true', help="write out all leaves to outfile")
    parser.add_argument('-hm', '--heatmap', action='store_true', help="generate a heatmap to outfile")
    parser.add_argument('-cb', '--colorbar', action='store_true', help="generate a colorbar on the heatmap")
    parser.add_argument('-n', '--appname', action='store', help="name to add to the text on the heatmap")
    parser.add_argument('-o', '--out', action='store', help="path to the output file")
    args = parser.parse_args()

    if args.label and len(args.label) != len(args.input):
        print("number of labels must match number of input files")
        exit(1)

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

    # result
    resdf = pd.DataFrame()
    if args.label:
        resdf['label'] = args.label
    resdf['paths'] = [df['trcount'].sum() for df in dfs]
    resdf['leaves'] = [df['trcount'].size for df in dfs]
    resdf['faults'] = [df['fcount'].sum() for df in dfs]

    # find all unique traces
    allleaves = pd.concat(dfs).drop_duplicates(['ip'])
    resdf['totalleaves'] = [allleaves['trcount'].size for _ in dfs]

    if args.writeleaves:
        # write out all leaves and exit
        scatterdf=pd.DataFrame()
        scatterdf['xcol'] = [args.label[i] if args.label else i for i in range(len(dfs))]
        leavescount = {}
        for ip in allleaves['ip'].values:
            leavescount[ip] = len([ip for df in dfs if ip in df['ip'].values])
        leavesidx={ip: i for i,ip in enumerate(sorted(leavescount, key=leavescount.get, reverse=True))}
        for ip, idx in leavesidx.items():
            scatterdf[ip] = [idx if ip in df['ip'].values else None for df in dfs]
        out = args.out if args.out else sys.stdout
        scatterdf.to_csv(out, index=False, header=True)
        return

    if args.heatmap:
        # generate heatmap and exit
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
        
        # plot heatmap
        heatmap = np.flip(heatmap, axis=1)  # flip x-values
        plt.rcParams["figure.figsize"] = (3.5 if args.colorbar else 3.2, 9)
        cmap = plt.cm.get_cmap('gist_heat_r')  # reversed hot
        # heatmap = np.where(heatmap == 0, np.nan, heatmap)
        # cmap.set_bad('c')
        plt.imshow(heatmap, cmap=cmap, origin='lower', interpolation='nearest',
            aspect='auto', extent=[0, heatmap.shape[1], 1, heatmap.shape[0]+1],
            vmin=0, vmax=50)
        if args.colorbar:
            cbar = plt.colorbar()
            cbar.ax.get_yaxis().labelpad = 10
            cbar.set_label('Fault Density', rotation=270)
        plt.xticks([5, 10, 15], ["25", "50", "75"])
        plt.xlabel("Local Memory %")
        plt.ylabel("Faulting Locations")
        # plt.yscale('log')
        if args.appname:    plt.title(args.appname)
        plt.tight_layout()
        plt.savefig(args.out if args.out else "heatmap.pdf")
        return
       
    # find traces unique to each file compared to all other files
    commonleaves = []
    commonleaves_faults = []
    for i, df in enumerate(dfs):
        idf = pd.concat([d for (j, d) in enumerate(dfs) if i != j]).drop_duplicates(['ip'])
        tempdf = pd.concat([df, idf, idf]).drop_duplicates(['ip'], keep=False)
        commonleaves.append(df['trcount'].size - tempdf['trcount'].size)
        commonleaves_faults.append(df['fcount'].sum() - tempdf['fcount'].sum())

    resdf['commonleaves_all'] = commonleaves
    resdf['commonfaults_all'] = commonleaves_faults

    # find traces unique to each file compared to previous and next file
    commonleaves = []
    commonleaves_faults = []
    for i, df in enumerate(dfs):
        prevdf = dfs[i-1] if i > 0 else None
        nextdf = dfs[i+1] if i < len(dfs)-1 else None
        idf = pd.concat([prevdf, nextdf]).drop_duplicates(['ip'])
        tempdf = pd.concat([df, idf, idf]).drop_duplicates(['ip'], keep=False)
        commonleaves.append(df['trcount'].size - tempdf['trcount'].size)
        commonleaves_faults.append(df['fcount'].sum() - tempdf['fcount'].sum())

    resdf['commonleaves_neighbors'] = commonleaves
    resdf['commonfaults_neighbors'] = commonleaves_faults

    # find traces unique to each file compared to previous file
    commonleaves = []
    commonleaves_faults = []
    for i, df in enumerate(dfs):
        prevdf = dfs[i-1] if i > 0 else None
        if prevdf is None:
            commonleaves.append(None)
            commonleaves_faults.append(None)
            continue
        idf = pd.concat([prevdf]).drop_duplicates(['ip'])
        tempdf = pd.concat([df, idf, idf]).drop_duplicates(['ip'], keep=False)
        commonleaves.append(df['trcount'].size - tempdf['trcount'].size)
        commonleaves_faults.append(df['fcount'].sum() - tempdf['fcount'].sum())
    
    resdf['commonleaves_right'] = commonleaves
    resdf['commonfaults_right'] = commonleaves_faults

    # find traces unique to each file compared to next file
    commonleaves = []
    commonleaves_faults = []
    for i, df in enumerate(dfs):
        nextdf = dfs[i+1] if i < len(dfs)-1 else None
        if nextdf is None:
            commonleaves.append(None)
            commonleaves_faults.append(None)
            continue
        idf = pd.concat([nextdf]).drop_duplicates(['ip'])
        tempdf = pd.concat([df, idf, idf]).drop_duplicates(['ip'], keep=False)
        commonleaves.append(df['trcount'].size - tempdf['trcount'].size)
        commonleaves_faults.append(df['fcount'].sum() - tempdf['fcount'].sum())

    resdf['commonleaves_left'] = commonleaves
    resdf['commonfaults_left'] = commonleaves_faults
    
    # write out
    out = args.out if args.out else sys.stdout
    resdf.to_csv(out, index=False, header=True)

if __name__ == '__main__':
    processed = 0
    main()
