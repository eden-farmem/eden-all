#
# Generic Python-based Plotter: Basically a CLI for matplotlib.
#   Generates various commonly used plot styles with a simple command 
#   Exposes useful matplotlib parameters/knobs (axes limits, labels, styles, etc) as command line options
#   Supports easy (command line) specification of data as columns from (multiple) CSV files
#
# Run "python plot.py -h" to see what it can do.
#
# AUTHOR: Anil Yelam
#
# SETUP
# 1. Python & pip
# 2. pip install matplotlib
#    sudo apt-get install  python-tk
#    pip install pandas
#    pip install scipy
#
#
# EXAMPLES:
# TODO 
#


import os
import matplotlib
import matplotlib.pyplot as plt
import argparse
import pandas as pd
import numpy as np
from enum import Enum
import scipy.stats as scstats


colors = ['b', 'g', 'r', 'brown', 'c','k', 'orange', 'm','orangered','y']
linetypes = ['g-','g--','g-+']
markers = ['o','x','+','s','+', '|', '^']

class PlotType(Enum):
    line = 'line'
    scatter = 'scatter'
    bar = 'bar'
    barstacked = 'barstacked'
    cdf = 'cdf'
    hist = 'hist'
    def __str__(self):
        return self.value

class LegendLoc(Enum):
    none = "none"
    best = 'best'
    topout = "topout"
    rightout = "rightout"
    rightin = "rightin"
    center = "center"

    def matplotlib_loc(self):
        if self.value == LegendLoc.none:       return None
        if self.value == LegendLoc.best:       return 'best'
        if self.value == LegendLoc.rightin:    return 'right'
        if self.value == LegendLoc.center:     return 'center'
        if self.value == LegendLoc.topout:     return 'lower left'
        if self.value == LegendLoc.rightout:   return 'upper left'

    def __str__(self):
        return self.value

def set_axes_legend_loc(ax, lns, labels, loc, title=None):
    if loc == LegendLoc.none:
        return
    if loc in (LegendLoc.best, LegendLoc.rightin, LegendLoc.center):
        ax.legend(lns, labels, loc=loc.matplotlib_loc(), ncol=1, fancybox=True, title=title)
    if loc == LegendLoc.topout:
        ax.legend(lns, labels, loc=loc.matplotlib_loc(), bbox_to_anchor=(0, 1, 1.2, 0.3), ncol=2, 
            fancybox=True, title=title)
    if loc == LegendLoc.rightout:
        ax.legend(lns, labels, loc=loc.matplotlib_loc(), bbox_to_anchor=(1.05, 1), ncol=1, 
            fancybox=True, title=title)


class LineStyle(Enum):
    solid = 'solid'
    dashed = "dashed"
    dotdash = "dashdot"

    def __str__(self):
        return self.value

class OutputFormat(Enum):
    pdf = 'pdf'
    png = "png"
    eps = "eps"

    def __str__(self):
        return self.value

def gen_cdf(npArray):
   x = np.sort(npArray)
   y = 1. * np.arange(len(npArray)) / (len(npArray) - 1)
   return x, y


# # PLOT ARGUMENTS
def parse_args():
    parser = argparse.ArgumentParser("Python Generic Plotter: Only accepts CSV files")

    # DATA SPECIFICATION (what do I plot?)
    parser.add_argument('-d', '--datafile', 
        action='append', 
        help='path to the data file. multiple values allowed, one for each curve')
        
    parser.add_argument('-xc', '--xcol', 
        action='store', 
        help='X column name from csv file. Defaults to row index if not provided.')

    parser.add_argument('-yc', '--ycol', 
        action='append', 
        help='Y column name from csv file. multiple values allowed, one for each curve')

    parser.add_argument('-dxc', '--dfilexcol', 
        nargs=2,
        action='store', 
        help='X column  from a specific csv file. Defaults to row index if not provided.')

    parser.add_argument('-dyc', '--dfileycol',          # (recommended way to specify data)
        nargs=2,
        action='append',
        metavar=('datafile', 'ycol'),
        help='Y column from a specific file that is included with this argument')

    # PLOT STYLE
    parser.add_argument('-z', '--ptype', 
        action='store', 
        help='type of the plot. Defaults to line',
        type=PlotType, 
        choices=list(PlotType), 
        default=PlotType.line)


    # PLOT METADATA (say something about the data)
    parser.add_argument('-t', '--ptitle', 
        action='store', 
        help='title of the plot')
    
    parser.add_argument('-l', '--plabel', 
        action='append', 
        help='plot label (empty string to skip), can provide one label per ycol or datafile (goes into legend)')
    
    parser.add_argument('-lt', '--ltitle', 
        action='store', 
        help='title on the plot legend',
        default=None)

    parser.add_argument('-xl', '--xlabel', 
        action='store', 
        help='Custom x-axis label')

    parser.add_argument('-yl', '--ylabel', 
        action='store', 
        help='Custom y-axis label')

    parser.add_argument('--xstr', 
        action='store_true', 
        help='treat x-values as text, not numeric (applies to a bar plot)',
        default=False)

    
    # PLOT ADD-ONS (give it a richer look)
    parser.add_argument('-xm', '--xmul', 
        action='store', 
        type=float,
        help='Custom x-axis multiplier constant (e.g., for unit conversion)',
        default=1)

    parser.add_argument('-ym', '--ymul', 
        action='store', 
        type=float,
        help='Custom y-axis multiplier constant (e.g., for unit conversion)',
        default=1)

    # TODO: better doc
    parser.add_argument('-yn', '--ynorm', 
        action='store_true', 
        help='Normalize plots a/c to the first plot',
        default=False)

    parser.add_argument('--xlog', 
        action='store_true', 
        help='Plot x-axis on log scale',
        default=False)
        
    parser.add_argument('--ylog', 
        action='store_true', 
        help='Plot y-axis on log scale',
        default=False)

    parser.add_argument('-hl', '--hlines', 
        action='store', 
        type=float,
        nargs='*',
        help='Add horizantal lines at specified y-values (multiple lines are allowed)')

    parser.add_argument('-hlf', '--hlinesfile', 
        action='store', 
        help='File with (label,xvalue) pairs for horizantal lines, one pair per line')
        
    parser.add_argument('-vl', '--vlines', 
        action='store', 
        type=float,
        nargs='*',
        help='Add vertical lines at specified x-values (multiple lines are allowed)')
    
    parser.add_argument('-vlf', '--vlinesfile', 
        action='store', 
        help='File with (label,xvalue) pairs for vertical lines, one pair per line')

    parser.add_argument('-tw', '--twin', 
        action='store', 
        type=int,
        help='add a twin y-axis for y cols starting from this index (count from 1)',
        default=100)
    
    parser.add_argument('-tyl', '--tylabel', 
        action='store', 
        help='Custom y-axis label for twin axis')
        
    parser.add_argument('-tym', '--tymul', 
        action='store', 
        type=float,
        help='Custom y-axis multiplier constant (e.g., to change units) for twin Y-axis',
        default=1)
    
    parser.add_argument('-tll', '--tlloc', 
        action='store', 
        help='Custom legend location for twin axis',
        type=LegendLoc, 
        choices=list(LegendLoc), 
        default=LegendLoc.best)
    
    
    # PLOT COSMETICS (it's all about look and feel)
    parser.add_argument('-ls', '--linestyle', 
        action='append', 
        help='line style of the plot of the plot. Can provide one label per ycol or datafile, defaults to solid',
        # type=LineStyle, 
        # choices=list(LineStyle))
    )

    parser.add_argument('-cmi', '--colormarkerincr', 
        action='append', 
        help='whether to move to the next color/marker pair, one per ycol or datafile',
        type=int
    )

    parser.add_argument('-li', '--labelincr', 
        action='append', 
        help='whether to move to the next label in the list, one per ycol or datafile',
        type=int
    )

    parser.add_argument('-nm', '--nomarker',  
        action='store_true', 
        help='dont add markers to plots', 
        default=False)
    
    parser.add_argument('-fs', '--fontsize', 
        action='store', 
        type=int,
        help='Font size of plot labels, ticks, etc',
        default=15)
    
    parser.add_argument('-ll', '--lloc', 
        action='store', 
        help='Custom legend location',
        type=LegendLoc, 
        choices=list(LegendLoc), 
        default=LegendLoc.best)

    parser.add_argument('-sz', '--size', 
        nargs=2,
        action='store',
        metavar=('width', 'height'),
        type=float,
        help='Custom plot size, Takes two args: height width',
        default=(8,4))

    parser.add_argument('-bw', '--barwidth', 
        action='store', 
        help='Set custom width for bars in a bar plot. Default: .5 in',
        type=float, 
        default=0.5)

    # PLOT SCOPING (move around on the cartesian plane)
    parser.add_argument('--xmin', 
        action='store', 
        type=float,
        help='Custom x-axis lower limit')

    parser.add_argument('--ymin', 
        action='store', 
        type=float,
        help='Custom y-axis lower limit')

    parser.add_argument('--xmax', 
        action='store', 
        type=float,
        help='Custom x-axis upper limit')

    parser.add_argument('--ymax', 
        action='store', 
        type=float,
        help='Custom y-axis upper limit')

    parser.add_argument('--tymin', 
        action='store', 
        type=float,
        help='Custom twin y-axis lower limit')

    parser.add_argument('--tymax', 
        action='store', 
        type=float,
        help='Custom twin y-axis upper limit')

    parser.add_argument('-nt', '--notail',  
        action='store', 
        help='eliminate last x%% tail from CDF. Defaults to 1%%', 
        nargs='?',
        type=float,
        const=0.1)

    parser.add_argument('-nh', '--nohead',  
        action='store', 
        help='eliminate first x%% head from CDF. Defaults to 1%%', 
        nargs='?',
        type=float,
        const=1.0)


    # LOGISTICS (boring stuff)
    parser.add_argument('-o', '--output', 
        action='store', 
        help='path to the generated output file (see -of for file format)', 
        default="result.png")
    
    parser.add_argument('-of', '--outformat', 
        action='store', 
        help='Output file format',
        type=OutputFormat, 
        choices=list(OutputFormat), 
        default=OutputFormat.pdf)

    parser.add_argument('-p', '--print_', 
        action='store_true', 
        help='print data (with nicer format) instead of plot', 
        default=False)

    parser.add_argument('-s', '--show',  
        action='store_true', 
        help='Display the plot after saving it. Blocks the program.', 
        default=False)

    args = parser.parse_args()
    return args


# All the messiness starts here!
def main():
    args = parse_args()

    # Plot can be: 
    # 1. One datafile with multiple ycolumns plotted against single xcolumn
    # 2. Single ycolumn from multiple datafiles plotted against an xcolumn
    # 3. If ycols from multiple datafiles must be plotted, use -dyc argument style
    dyc=(args.dfileycol is not None)
    dandyc=(args.datafile is not None or args.ycol is not None)
    if (dyc and dandyc) or not (dyc or dandyc):
        parser.error("Use either the (-dyc) or the (-d and -yc) approach exclusively, not both!")

    if (args.datafile or args.ycol) and \
        (args.datafile and len(args.datafile) > 1) and \
        (args.ycol and len(args.ycol) > 1):
        parser.error("Only one of datafile or ycolumn arguments can provide multiple values. Use -dyc style if this doesn't work for you.")
    
    if args.xcol and args.dfilexcol:
        parser.error("Use either the -dxc or -xc to specify xcol, not both!")

    # Infer data files, xcols and ycols from args
    num_plots = 0
    dfile_ycol_map = []     #Maintain the input order
    if args.dfileycol:
        for (dfile, ycol) in args.dfileycol:
            dfile_ycol_map.append((dfile, ycol))
            num_plots += 1
    else:
        for dfile in args.datafile:
            for ycol in args.ycol:
                dfile_ycol_map.append((dfile, ycol))
                num_plots += 1  

    if not args.labelincr and args.plabel and len(args.plabel) != num_plots:
        parser.error("If plot labels are provided and --labelincr is not, they must be provided for all the plots and are mapped one-to-one in input order")
    
    if args.labelincr:
        if not args.plabel:
            parser.error("If --labelincr is specified, plot labels must be specified with -l/--plabel")
        if len(args.plabel) < sum(args.labelincr):
            parser.error("If plot labels and --labelincr are provided, sum of label increments should not cross the number of plot labels")
    
    if (args.nohead or args.notail) and args.ptype != PlotType.cdf:
        parser.error("head and tail trimming is only supported for CDF plots (-z/--ptype: cdf)")

    xlabel = args.xlabel if args.xlabel else args.xcol
    ylabel = args.ylabel if args.ylabel else dfile_ycol_map[0][1]

    cidx = 0
    midx = 0
    lidx = 0
    aidx = 0
    labelidx = 0

    font = {'family' : 'sans-serif',
            'size'   : args.fontsize}
    matplotlib.rc('font', **font)
    matplotlib.rc('figure', autolayout=True)
    matplotlib.rc('figure', autolayout=True)
    matplotlib.rcParams['pdf.fonttype'] = 42        # required for latex embedded figures

    fig, axmain = plt.subplots(1, 1, figsize=tuple(args.size))
    if args.ptitle:
        fig.suptitle(args.ptitle, x=0.3, y=0.9, \
            horizontalalignment='left', verticalalignment='top')
        fig.tight_layout()

    if args.xlog:
        axmain.set_xscale('log', basex=10)
    if args.ylog:
        axmain.set_yscale('log')

    xcol = None
    if args.dfilexcol:
        df = pd.read_csv(args.dfilexcol[0],skipinitialspace=True)
        xcol = df[args.dfilexcol[1]]

    plot_num = 0
    lns = []
    labels = []
    ax = axmain
    ymul = args.ymul
    ymin = args.ymin
    ymax = args.ymax
    base_dataset = None
    for (datafile, ycol) in dfile_ycol_map:

        if (plot_num + 1) == args.twin:
            # Switch to twin axis, reset Y-axis settings
            ax = axmain.twinx()
            ylabel = args.tylabel if args.tylabel else ycol
            ymul = args.tymul
            ymin = args.tymin
            ymax = args.tymax

        if not os.path.exists(datafile):
            print("Datafile {0} does not exist".format(datafile))
            return -1

        df = pd.read_csv(datafile, skipinitialspace=True)
        if args.print_:
            label = "{0}:{1}".format(datafile, ycol)
            print(label, df[ycol].mean(), df[ycol].std())
            continue

        if args.plabel:                 label = args.plabel[labelidx] if args.labelincr else args.plabel[plot_num]
        elif len(args.datafile) == 1:   label = ycol
        else:                           label = datafile
        labels.append(label)

        if not args.dfilexcol:
            xcol = df[args.xcol] if args.xcol else df.index

        if args.ptype == PlotType.line:
            xc = xcol
            yc = df[ycol]
            xc = [x * args.xmul for x in xc]
            yc = [y * ymul for y in yc]

            if args.ynorm:
                if plot_num == 0:   
                    base_dataset = yc
                    yc = [1 for _ in yc]
                else:
                    yc = [i/j for i,j in zip(yc,base_dataset)]

            if args.xstr:   xc = [str(x) for x in xc]
            lns += ax.plot(xc, yc, label=label, color=colors[cidx],
                marker=(None if args.nomarker else markers[midx]),
                markerfacecolor=(None if args.nomarker else colors[cidx]))
            # if args.xstr:   ax.set_xticks(xc)
            # if args.xstr:   ax.set_xticklabels(xc, rotation='45')     

        elif args.ptype == PlotType.scatter:
            xc = xcol
            yc = df[ycol]
            xc = [x * args.xmul for x in xc]
            yc = [y * ymul for y in yc]
            marker_size = 2*(72./fig.dpi)**2 if len(yc) > 1000 else None
            ax.scatter(xc, yc, label=label, color=colors[cidx],
                marker=(None if args.nomarker else markers[midx]), s=marker_size)
            if args.xstr:   ax.set_xticks(xc)
            if args.xstr:   ax.set_xticklabels(xc, rotation='45')     

        elif args.ptype == PlotType.bar:
            xstart = np.arange(len(xcol)) * (num_plots + 1) * args.barwidth
            xc = xstart + plot_num * args.barwidth
            yc = df[ycol]
            xc = [x * args.xmul for x in xc]
            yc = [y * ymul for y in yc]
            ax.bar(xc, yc, width=args.barwidth, label=label, color=colors[cidx])
            if plot_num == num_plots - 1:
                xticks = xstart + (num_plots - 1) * args.barwidth / 2
                ax.set_xticks(xticks)
                ax.set_xticklabels(xcol, rotation='15' if args.xstr else 0) 

        elif args.ptype == PlotType.barstacked:
            xc = xcol
            yc = df[ycol]
            xc = [x * args.xmul for x in xc]
            yc = np.array([y * ymul for y in yc])
            if args.xstr:   xc = [str(x) for x in xc]
            ax.bar(xc, yc, bottom=base_dataset, label=label, color=colors[cidx])
            if plot_num == num_plots - 1:
                ax.set_xticks(xc)
                ax.set_xticklabels(xc, rotation='15' if args.xstr else 0)
            base_dataset = yc if base_dataset is None else base_dataset + yc

        elif args.ptype == PlotType.hist:
            raise NotImplementedError("hist")

        elif args.ptype == PlotType.cdf:
            xc, yc = gen_cdf(df[ycol])

            # See if head and/or tail needs trimming
            # NOTE: We don't remove values, instead we limit the axes. This is essentially 
            # zooming in on a CDF when the head or tail is too long
            head = None
            tail = None
            if args.nohead:
                for i, val in enumerate(yc):
                    if val <= args.nohead/100.0:
                        head = xc[i]
                if head:
                    args.xmin = head if args.xmin is None else min(head, args.xmin)
            if args.notail:
                for i, val in enumerate(yc):
                    if val > (100.0 - args.notail)/100.0:
                        tail = xc[i]
                        break
                if tail:
                    args.xmax = tail if args.xmax is None else max(tail, args.xmax)
            
            xc = [x * args.xmul for x in xc]
            yc = [y * ymul for y in yc]
            lns += ax.plot(xc, yc, label=label, color=colors[cidx],
                marker=(None if args.nomarker else markers[midx]))
                # markerfacecolor=(None if args.nomarker else colors[cidx]))

            # Add a line at mode (TODO: make this a command line option)
            # mode = scstats.mode(xc).mode[0]
            # if not args.vlines:     args.vlines = []
            # args.vlines.append(mode)        
            ylabel = "CDF"

        if args.colormarkerincr:
            if args.colormarkerincr[plot_num] == 1:
                cidx = (cidx + 1) % len(colors)
                midx = (midx + 1) % len(markers)
        else:
            cidx = (cidx + 1) % len(colors)
            midx = (midx + 1) % len(markers)
     
        if args.labelincr:
            if args.labelincr[plot_num] == 1:
                labelidx = (labelidx + 1)
        
        plot_num += 1
        if ymin is not None and ymax is not None: ax.set_ylim(ymin=ymin,ymax=ymax)
        elif ymin is not None:    ax.set_ylim(ymin=ymin)
        elif ymax is not None:    ax.set_ylim(ymax=ymax)
        ax.set_ylabel(ylabel)

    # print(args.xmin, args.xmax)
    if args.xmin is not None:   axmain.set_xlim(xmin=args.xmin)
    if args.xmax is not None:   axmain.set_xlim(xmax=args.xmax)
    # plt.ylim(args.ymin, args.ymax)

    axmain.set_xlabel(xlabel)
    # axmain.set_ylabel(ylabel)
    # ax.ticklabel_format(useOffset=False, style='plain')

    if args.linestyle:
        for idx, ls in enumerate(args.linestyle):
            lns[idx].set_linestyle(ls)
    
    if args.lloc != LegendLoc.none and \
            args.ptype in [PlotType.scatter, PlotType.bar, PlotType.barstacked, PlotType.hist]:
        # FIXME: We don't get ln objects for these plot types. So legends generated in this path 
        # miss some custom features like the ability to skip some labels or legend location
        plt.legend(loc=args.lloc.matplotlib_loc(), title=args.ltitle)
    else:
        # Skip a label if an empty string is provided
        labels_adjusted = [l for l in labels if l != ""]
        lns_adjusted = [l for i,l in enumerate(lns) if labels[i] != ""]
        set_axes_legend_loc(axmain, lns_adjusted, labels_adjusted, args.lloc, args.ltitle)

    # Add any horizantal and/or vertical lines
    if args.hlines:
        for hline in args.hlines:
            plt.axhline(y=hline, ls='dashed')
            plt.text(0.5, hline, str(hline), transform=axmain.get_yaxis_transform(), 
                color='black', fontsize='small')
    if args.vlines:
        for vline in args.vlines:
            plt.axvline(x=vline, ls='dashed')
            plt.text(vline, 0.1, str(vline), transform=axmain.get_xaxis_transform(), 
                color='black', fontsize='small',rotation=90)
    if args.vlinesfile:
        if os.path.exists(args.vlinesfile):
            with open(args.vlinesfile) as f:
                for line in f.readlines():
                    label = line.split(",")[0]
                    xval = int(line.split(",")[1])
                    plt.axvline(x=xval, ls='dashed', color='black')
                    plt.text(xval, 0.3, str(label), transform=axmain.get_xaxis_transform(), 
                        color='black', fontsize='small',rotation=90)


    # plt.savefig(args.output, format="eps")
    plt.savefig(args.output, format=str(args.outformat))
    if args.show:
        plt.show()

if __name__ == '__main__':
    main()