import argparse
from enum import Enum
import os
import sys
import subprocess
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

APPS_ALL = {
    "blackscholes": { "group": "parsec", "short": "bscholes" },
    "canneal": { "group": "parsec", "short": "canneal" },
    "dedup": { "group": "parsec", "short": "dedup" },
    "facesim": { "group": "parsec", "short": "facesim" },
    "ferret": { "group": "parsec", "short": "ferret" },
    "fluidanimate": { "group": "parsec", "short": "fluid" },
    "raytrace": { "group": "parsec", "short": "raytrace" },
    "vips": { "group": "parsec", "short": "vips" },
    "x264": { "group": "parsec", "short": "x264" },
    "rocksdb": { "group": "kvs", "short": "rocksdb" },
    "leveldb": { "group": "kvs", "short": "leveldb" },
    "redis": { "group": "kvs", "short": "redis" },
    "mcached": { "group": "kvs", "short": "memcached" },
    "apsp": { "group": "graph", "short": "apsp" },
    "bfs": { "group": "graph", "short": "bfs" },
    "connected-components": { "group": "graph", "short": "cc" },
    "pagerank": { "group": "graph", "short": "pagerank" },
    "sssp": { "group": "graph", "short": "pagerank" },
    "triangle-counting": { "group": "graph", "short": "tc" },
    "dfs": { "group": "graph", "short": "dfs" },
    "sssp": { "group": "graph", "short": "sssp" },
}

APPS = APPS_ALL
PERCENT = 100

def main():

    # read data
    data = {}
    for app in APPS.keys():
        fname = 'data/heatmap_{}_{}.txt'.format(app, PERCENT)
        if not os.path.exists(fname):
            print("can't locate input file: {}".format(fname))
            exit(1)
        data[app] = np.loadtxt(fname, delimiter=',')

    # cmap
    cmap = plt.cm.get_cmap('gist_heat_r')  # reversed hot
    # # heatmap = np.where(heatmap == 0, np.nan, heatmap)
    # # cmap.set_bad('c')

    ROWS = 4
    COLS = 6
    fig = plt.figure(constrained_layout=True, figsize=(12, 9))
    axes = fig.subplots(ROWS, COLS, sharex=True)
    
    count = 0
    cbar_ax = []
    for (i, j), ax in np.ndenumerate(axes):
        if count >= len(data):
            break

        name = list(APPS.keys())[count]
        heatmap = data[name]
        count += 1
        print(name)

        mpax = ax.imshow(heatmap, cmap=cmap, origin='lower', interpolation='nearest',
            aspect='auto', extent=[0, heatmap.shape[1], 1, heatmap.shape[0]+1],
            vmin=0, vmax=50)
        if j == COLS-1:
            cbar_ax.append(ax)

        ax.set_yscale('log')
        ax.set_title("{} ({})".format(APPS[name]["short"], APPS[name]["group"].upper()[0]))
        if j == 0:  ax.set_ylabel("Faulting Locations")
        if i == ROWS-1: ax.set_xlabel("Local Memory %")

    # colorbar
    cbar = plt.colorbar(mpax, ax=cbar_ax if cbar_ax else None)
    cbar.ax.get_yaxis().labelpad = 10
    cbar.set_label('Fault Density', rotation=270)

    # ticks and labels
    plt.xticks([5, 10, 15], ["25", "50", "75"])
    plt.xlabel("Local Memory %")

    # save
    plt.show()
    # plt.savefig("heatmap.pdf")

if __name__ == "__main__":
    main()