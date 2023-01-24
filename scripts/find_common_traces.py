import argparse
from enum import Enum
import os
import sys
import subprocess
import pandas as pd

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
    parser.add_argument('-o', '--out', action='store', help="path to the output file")
    args = parser.parse_args()

    if args.label and len(args.label) != len(args.input):
        print("number of labels must match number of input files")
        exit(1)

    # read in
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
        dfs.append(tempdf)

    # result
    resdf = pd.DataFrame()
    if args.label:
        resdf['label'] = args.label
    resdf['paths'] = [df['trcount'].sum() for df in dfs]
    resdf['leaves'] = [df['trcount'].size for df in dfs]
    resdf['faults'] = [df['fcount'].sum() for df in dfs]

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
