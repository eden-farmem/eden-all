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


colors = ['r', 'b', 'g', 'brown', 'c', 'k', 'orange', 'm','orangered','y']
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
    top = "top"
    topout = "topout"
    rightout = "rightout"
    rightin = "rightin"
    center = "center"

    def matplotlib_loc(self):
        if self.value == LegendLoc.none:       return None
        if self.value == LegendLoc.best:       return 'best'
        if self.value == LegendLoc.rightin:    return 'right'
        if self.value == LegendLoc.center:     return 'center'
        if self.value == LegendLoc.top:     return 'upper center'
        if self.value == LegendLoc.topout:     return 'lower left'
        if self.value == LegendLoc.rightout:   return 'upper left'

    def __str__(self):
        return self.value

def set_axes_legend_loc(ax, lns, labels, loc, title=None):
    if loc == LegendLoc.none:
        return
    if loc in (LegendLoc.best, LegendLoc.rightin, LegendLoc.center, LegendLoc.top):
        ax.legend(lns, labels, loc=loc.matplotlib_loc(), ncol=1, fancybox=True, title=title)
    if loc == LegendLoc.topout:
        ax.legend(lns, labels, loc=loc.matplotlib_loc(), bbox_to_anchor=(0, 1, 1.2, 0.3), ncol=2,
            fancybox=True, title=title)
    if loc == LegendLoc.rightout:
        ax.legend(lns, labels, loc=loc.matplotlib_loc(), bbox_to_anchor=(1.05, 1), ncol=1,
            fancybox=True, title=title)

def set_plot_legend_loc(plt, loc, title=None):
    if loc == LegendLoc.none:
        return
    if loc in (LegendLoc.best, LegendLoc.rightin, LegendLoc.center, LegendLoc.top):
        plt.legend(loc=loc.matplotlib_loc(), ncol=1, fancybox=True, title=title)
    if loc == LegendLoc.topout:
        plt.legend(loc="lower left", bbox_to_anchor=(-.5, 1, 1, 0.8), ncol=1,
            fancybox=True, title=title)
    if loc == LegendLoc.rightout:
        plt.legend(loc=loc.matplotlib_loc(), bbox_to_anchor=(1.05, 1), ncol=1,
            fancybox=True, title=title)


LINESTYLE_TUPLES = {
    'solid':               (0, ()),
    'loosedot':            (0, (1, 10)),
    'dotted':              (0, (1, 5)),
    'densedot':            (0, (1, 1)),
    'loosedash':           (0, (5, 10)),
    'dashed':              (0, (5, 5)),
    'densedash':           (0, (5, 1)),
    'loosedashdot':        (0, (3, 10, 1, 10)),
    'dashdot':             (0, (3, 5, 1, 5)),
    'densedashdot':        (0, (3, 1, 1, 1)),
    'loosedashdotdot':     (0, (3, 10, 1, 10, 1, 10)),
    'dashdotdot':          (0, (3, 5, 1, 5, 1, 5)),
    'densedashdotdot':     (0, (3, 1, 1, 1, 1, 1))
}

class LineStyle(Enum):
    """ Enumerates matplotlib linestyles """
    SOLID = 'solid'
    LOOSEDOT = 'loosedot'
    DOTTED = 'dotted'
    DENSEDOT = 'densedot'
    LOOSEDASH = 'loosedash'
    DASHED = "dashed"
    DENSEDASH = 'densedash'
    LOOSEDASHDOT = "loosedashdot"
    DASHDOT = 'dashdot'
    DENSEDASHDOT = 'densedashdot'
    LOOSEDASHDOTDOT = 'loosedashdotdot'
    DASHDOTDOT = 'dashdotdot'
    DENSEDASHDOTDOT = 'densedashdotdot'
    def __str__(self):
        return self.value
    def tuple_value(self):
        return LINESTYLE_TUPLES[self.value]

class BarHatchStyle(Enum):
    """ Enumerates matplotlib bar hatch patterns """
    DIAGONAL = '/'
    BACKDIAGONAL = '\\'
    VERTICAL = '|'
    SMALLCIRLCE = 'o'
    BIGCIRCLE = 'O'
    DOTS = '.'
    STARS = '*'
    def __str__(self):
        return self.value

class OutputFormat(Enum):
    """ Enumerates output formats """
    PDF = 'pdf'
    PNG = "png"
    EPS = "eps"
    def __str__(self):
        return self.value

def gen_cdf(npArray):
   x = np.sort(npArray)
   y = 1. * np.arange(len(npArray)) / (len(npArray) - 1)
   return x, y

def gen_cdf_from_pdf(xc, yc):
   return xc, np.cumsum(yc)/sum(yc)

def parser_definition():
    """ Parser Definition """

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

    parser.add_argument('-dyc', '--dfileycol',
        nargs=2,
        action='append',
        metavar=('datafile', 'ycol'),
        help='Y column from a specific file that is included with this argument')

    parser.add_argument('-dyce', '--dfileycolyerr',
        nargs=3,
        action='append',
        metavar=('datafile', 'ycol', 'yerr'),
        help='Y column and Y error for error bars')

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

    parser.add_argument('-pd', '--pdfdata',
        action='store_true',
        help='Treat the provided data as PDF when generating and plotting CDF',
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

    # MISC
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
        help='Custom line style for each plot, one per plot',
        type=LineStyle,
        choices=list(LineStyle))

    parser.add_argument('-bhs', '--barhatchstyle',
        action='append',
        help='Custom bar hatch style of the bar plot, one per plot',
        type=BarHatchStyle,
        choices=list(BarHatchStyle))

    parser.add_argument('-bs', '--barstack',
        action='append',
        help='Custom bar chart stacking option, one per plot',
        type=int)

    parser.add_argument('-cmi', '--colormarkerincr',
        action='append',
        help='whether to move to the next color/marker pair, one per ycol or datafile',
        type=int)

    parser.add_argument('-li', '--labelincr',
        action='append',
        help='whether to move to the next label in the list, one per ycol or datafile',
        type=int)

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
        default=OutputFormat.PDF)

    parser.add_argument('-p', '--print_',
        action='store_true',
        help='print data (with nicer format) instead of plot',
        default=False)

    parser.add_argument('-s', '--show',
        action='store_true',
        help='Display the plot after saving it. Blocks the program.',
        default=False)

    return parser

def main():
    """ Main workflow. Super messy! """
    parser = parser_definition()
    args = parser.parse_args()

    # Plot can be: 
    # 1. One datafile with multiple ycolumns plotted against single xcolumn
    # 2. Single ycolumn from multiple datafiles plotted against an xcolumn
    # 3. If ycols from multiple datafiles must be plotted, use -dyc argument style
    dyce=(args.dfileycolyerr is not None)
    dyc=(args.dfileycol is not None)
    dandyc=(args.datafile is not None or args.ycol is not None)
    if not (dyc or dandyc or dyce):
        parser.error("Provide inputs using either -d/-yc or -dyc or -dyce!")

    if (args.datafile or args.ycol) and \
        (args.datafile and len(args.datafile) > 1) and \
        (args.ycol and len(args.ycol) > 1):
        parser.error("Only one of datafile or ycolumn arguments can provide multiple values. Use -dyc style if this doesn't work for you.")

    if args.xcol and args.dfilexcol:
        parser.error("Use either the -dxc or -xc to specify xcol, not both!")

    # Infer data files, xcols and ycols from args
    num_plots = 0
    dfile_ycol_yerr_map = []     #Maintain the input order
    if args.dfileycolyerr:
        for (dfile, ycol, yerr) in args.dfileycolyerr:
            dfile_ycol_yerr_map.append((dfile, ycol, yerr if yerr else None))
            num_plots += 1
    elif args.dfileycol:
        for (dfile, ycol) in args.dfileycol:
            dfile_ycol_yerr_map.append((dfile, ycol, None))
            num_plots += 1
    else:
        for dfile in args.datafile:
            for ycol in args.ycol:
                dfile_ycol_yerr_map.append((dfile, ycol, None))
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
    ylabel = args.ylabel if args.ylabel else dfile_ycol_yerr_map[0][1]

    cidx = 0
    midx = 0
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
    xc = None
    total_width = 0
    for (datafile, ycol, yerr) in dfile_ycol_yerr_map:

        if (plot_num + 1) == args.twin:
            # Switch to twin axis, reset Y-axis settings
            # save plotted objects before switching
            lns_, labels_ = ax.get_legend_handles_labels()
            lns += lns_
            labels += labels_

            ax = axmain.twinx()
            ylabel = args.tylabel if args.tylabel else ycol
            ymul = args.tymul
            ymin = args.tymin
            ymax = args.tymax
            # Set the twin axis to the same color as the first twin plot
            ax.spines['right'].set_color(colors[cidx])
            ax.tick_params(axis='y', colors=colors[cidx])
            ax.yaxis.label.set_color(colors[cidx])

        if not os.path.exists(datafile):
            print("datafile {} does not exist".format(datafile))
            return -1

        df = pd.read_csv(datafile, skipinitialspace=True)
        if args.print_:
            label = "{}:{}".format(datafile, ycol)
            print(label, df[ycol].mean(), df[ycol].std())
            continue

        if args.plabel:                 label = args.plabel[labelidx] if args.labelincr else args.plabel[plot_num]
        elif len(args.datafile) == 1:   label = ycol
        else:                           label = datafile

        if not args.dfilexcol:
            xcol = df[args.xcol] if args.xcol else df.index

        if args.ptype == PlotType.line:
            xc = xcol
            yc = df[ycol]
            ye = df[yerr] if yerr else None

            xc = [x * args.xmul for x in xc]
            yc = [y * ymul for y in yc]
            ye = [y * ymul for y in ye] if ye is not None else None

            if args.ynorm:
                if plot_num == 0:   
                    base_dataset = yc
                    yc = [1 for _ in yc]
                else:
                    yc = [i/j for i,j in zip(yc,base_dataset)]

            if args.xstr:   
                xc = [str(x) for x in xc]
            ax.errorbar(xc, yc, yerr=ye, label=label, color=colors[cidx],
                marker=(None if args.nomarker else markers[midx]),
                markerfacecolor=(None if args.nomarker else colors[cidx]),
                ls=args.linestyle[plot_num] if args.linestyle is not None else None)
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
            if xc is None:  xc = xstart
            yc = df[ycol]
            if args.xmul is not None:
                xc *= args.xmul
            yc = [y * ymul for y in yc]

            ax.bar(xc, yc, width=args.barwidth, bottom=base_dataset,
                label=None if label.isspace() else label, color=colors[cidx],
                hatch=str(args.barhatchstyle[plot_num]) if args.barhatchstyle is not None else None)

            # ax.set_xticklabels(xcol, rotation='15' if args.xstr else 0)
            if args.barstack and args.barstack[plot_num] == 1:
                if base_dataset is None:    base_dataset = yc
                else:   base_dataset = [a + b for a, b in zip(base_dataset, yc)]
            else:   
                base_dataset = None
                xc = xc + args.barwidth
                total_width += args.barwidth
            
            if plot_num == num_plots - 1:
                xticks = xstart + total_width / 2
                ax.set_xticks(xticks)
                ax.set_xticklabels(xcol)

        elif args.ptype == PlotType.barstacked:
            xc = xcol
            yc = df[ycol]
            xc = [x * args.xmul for x in xc]
            yc = np.array([y * ymul for y in yc])
            if args.xstr:   
                xc = [str(x) for x in xc]
            ax.bar(xc, yc, width=args.barwidth, bottom=base_dataset, label=label, color=colors[cidx])
            if plot_num == num_plots - 1:
                ax.set_xticks(xc)
                ax.set_xticklabels(xc, rotation='15' if args.xstr else 0)
            base_dataset = yc if base_dataset is None else base_dataset + yc

        elif args.ptype == PlotType.hist:
            raise NotImplementedError("hist")

        elif args.ptype == PlotType.cdf:
            xc, yc = gen_cdf_from_pdf(xcol, df[ycol]) if args.pdfdata else gen_cdf(df[ycol])

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
            ax.step(xc, yc, label=label, color=colors[cidx], where="post",
                marker=(None if args.nomarker else markers[midx]),
                ls=args.linestyle[plot_num] if args.linestyle is not None else None)
                # markerfacecolor=(None if args.nomarker else colors[cidx]))

            # # Add a line at median (TODO: make this a command line option)
            # median = statistics.median(xc)
            # if not args.vlines:     args.vlines = []
            # args.vlines.append(median)
            ylabel = "CDF"

        if args.colormarkerincr:
            cidx = (cidx + args.colormarkerincr[plot_num]) % len(colors)
            midx = (midx + args.colormarkerincr[plot_num]) % len(markers)
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

    # collect plotted objects
    lns_, labels_ = ax.get_legend_handles_labels()
    lns += lns_
    labels += labels_

    if args.lloc != LegendLoc.none and \
            args.ptype in [PlotType.scatter, PlotType.bar, PlotType.barstacked, PlotType.hist]:
        # FIXME: We don't get ln objects for these plot types. So legends generated in this path 
        # miss some custom features like the ability to skip some labels or legend location
        # plt.legend(loc="upper center", title=args.ltitle)
        set_plot_legend_loc(plt, args.lloc, args.ltitle)
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