"""
Generic Python-based Plotter: Basically a CLI for matplotlib.
  - Generates various commonly used plot styles with a simple command
  - Exposes useful matplotlib parameters/knobs (axes limits, labels, styles,
  etc.) as command line options
  - Supports easy (command line) specification of data as columns from
  (multiple) CSV files

Run "python plot.py -h" to see what it can do.

AUTHOR: Anil Yelam

SETUP
1. Python & pip
2. pip install matplotlib
   sudo apt-get install python-tk
   pip install pandas
   pip install scipy

EXAMPLES:
TODO
"""
# pylint: disable=consider-using-f-string,multiple-statements,wrong-import-position

import os
import argparse
from enum import Enum
import matplotlib
matplotlib.use('Agg')   # to avoid gdk_cursor_new_for_display warning
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

COLORS = ['r', 'b', 'g', 'brown', 'c', 'k', 'orange', 'm','orangered','y']
MARKERS = ['o','x','+','s','+', '|', '^']

class PlotType(Enum):
    """ Available charts """
    LINE = 'line'
    SCATTER = 'scatter'
    BAR = 'bar'
    CDF = 'cdf'
    def __str__(self):
        return self.value

class LegendLoc(Enum):
    """ References to Matplotlib legend postions """
    NONE = "none"
    BEST = 'best'
    TOP = "top"
    TOPOUT = "topout"
    RIGHTOUT = "rightout"
    RIGHTIN = "rightin"
    CENTER = "center"
    def _as_matplotlib_loc(self):
        if self.value == LegendLoc.NONE:        return None
        if self.value == LegendLoc.BEST:        return 'best'
        if self.value == LegendLoc.RIGHTIN:     return 'right'
        if self.value == LegendLoc.CENTER:      return 'center'
        if self.value == LegendLoc.TOP:         return 'upper center'
        if self.value == LegendLoc.TOPOUT:      return 'lower left'
        if self.value == LegendLoc.RIGHTOUT:    return 'upper left'
    def __str__(self):
        return self.value
    def add_legend(self, axes, lns, labels, title=None):
        """ Adds legend at the given location """
        ncol = 1
        loc = self._as_matplotlib_loc()
        bbox_to_anchor = None
        fancybox = True
        if self.value == LegendLoc.NONE:
            return
        if self.value == LegendLoc.TOPOUT:
            bbox_to_anchor = (0, 1, 1.2, 0.3)
            ncol = 2
        if self.value == LegendLoc.RIGHTOUT:
            bbox_to_anchor = (1.05, 1)
        axes.legend(lns, labels, loc=loc, ncol=ncol, fancybox=fancybox,
            bbox_to_anchor=bbox_to_anchor, title=title)

LINESTYLE_TUPLES = {
    'solid':               (0, ()),
    'dashed':              (0, (5, 5)),
    'dotted':              (0, (1, 5)),
    'dashdot':             (0, (3, 5, 1, 5)),
    'dashdotdot':          (0, (3, 5, 1, 5, 1, 5)),
    'loosedash':           (0, (5, 10)),
    'loosedot':            (0, (1, 10)),
    'loosedashdot':        (0, (3, 10, 1, 10)),
    'loosedashdotdot':     (0, (3, 10, 1, 10, 1, 10)),
    'densedash':           (0, (5, 1)),
    'densedot':            (0, (1, 1)),
    'densedashdot':        (0, (3, 1, 1, 1)),
    'densedashdotdot':     (0, (3, 1, 1, 1, 1, 1))
}

class LineStyle(Enum):
    """ Enumerates some matplotlib linestyles """
    SOLID = 'solid'
    DASHED = 'dashed'
    DOTTED = 'dotted'
    DASHDOT = 'dashdot'
    DASHDOTDOT = 'dashdotdot'
    # LOOSEDASH = 'loosedash'       (more options, uncomment if needed)
    # LOOSEDOT = 'loosedot'
    # LOOSEDASHDOT = 'loosedashdot
    # LOOSEDASHDOTDOT = 'loosedashdotdot'
    # DENSEDASH = 'densedash'
    # DENSEDOT = 'densedot'
    # DENSEDASHDOT = 'densedashdot'
    # DENSEDASHDOTDOT = 'densedashdotdot'
    def __str__(self):
        return self.value
    def as_tuple(self):
        """ Linestyle as matplotlib tuple """
        return LINESTYLE_TUPLES[self.value]

class BarHatchStyle(Enum):
    """ Enumerates some matplotlib bar hatch patterns """
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
    """ Enumerates output file formats """
    PDF = 'pdf'
    PNG = "png"
    EPS = "eps"
    def __str__(self):
        return self.value

class Plot:
    """ Encapuslates some varying metadata for each plot """
    ydatafile = None
    ycolumn = None
    yerror = None
    xdatafile = None
    xcolumn = None
    label = None
    is_twin = False
    def __init__(self, yfile, ycol, yerr, xfile, xcol):
        self.ydatafile = yfile
        self.ycolumn = ycol
        self.yerror = yerr
        self.xdatafile = xfile
        self.xcolumn = xcol
    def read_xcolumn(self):
        "read and return x-column data for this plot"
        if not self.xcolumn: return None
        xdatafile = self.xdatafile if self.xdatafile else self.ydatafile
        assert os.path.exists(xdatafile), "x-column datafile not found"
        dframe = pd.read_csv(xdatafile, skipinitialspace=True)
        return dframe[self.xcolumn]
    def read_ycolumn(self):
        "read and return y-column data for this plot"
        assert self.ycolumn is not None, "y-column must be present"
        assert os.path.exists(self.ydatafile), "y-column datafile not found"
        dframe = pd.read_csv(self.ydatafile, skipinitialspace=True)
        return dframe[self.ycolumn]
    def read_yerror(self):
        "read and return y-error data for this plot"
        if not self.yerror: return None
        assert os.path.exists(self.ydatafile), "y-error datafile not found"
        dframe = pd.read_csv(self.ydatafile, skipinitialspace=True)
        return dframe[self.yerror]

def parser_definition():
    """ Parser Definition """

    parser = argparse.ArgumentParser("Python Generic Plotter: Only accepts "
        "CSV files")

    # DATA SPECIFICATION (what do I plot?)
    parser.add_argument('-d', '--datafile',
        action='append',
        help='Path to the data file. Multiple values are allowed, each '
            'representing a CSV file containing a column referenced to by [-yc]')

    parser.add_argument('-xc', '--xcolumn',
        action='store',
        help='CSV column name for X-coordinate. Looks up the column in the same'
            ' file as corresponding Y-column. Defaults to the row index '
            ' if not provided.')

    parser.add_argument('-yc', '--ycolumn',
        action='append',
        help='CSV column name for Y-coordinate. Multiple values are allowed, '
            'each representing a column from the CSV file [-d] that is plotted '
            'separately')

    parser.add_argument('-yce', '--ycolumnyerr',
        nargs=2,
        action='append',
        metavar=('YCOLUMN', 'YERROR'),
        help='Like -yc but along with an error bar column for each Y-column')

    parser.add_argument('-dxc', '--dfilexcol',
        nargs=2,
        action='store',
        metavar=('XDATAFILE', 'XCOLUMN'),
        help='Like -xcol but also specify a CSV file for the X-column for all plots')

    parser.add_argument('-dyc', '--dfileycol',
        nargs=2,
        action='append',
        metavar=('YDATAFILE', 'YCOLUMN'),
        help='Like -ycol but also specify a separate CSV file per Y-column')

    parser.add_argument('-dyce', '--dfileycolyerr',
        nargs=3,
        action='append',
        metavar=('YDATAFILE', 'YCOLUMN', 'YERROR'),
        help='Like -dycol but along with an error bar column for each Y-column')

    # PLOT STYLE
    parser.add_argument('-z', '--ptype',
        action='store',
        help='Type of the plot. Defaults to a line chart',
        type=PlotType,
        choices=list(PlotType),
        default=PlotType.LINE)

    parser.add_argument('-tw', '--twin',
        action='store',
        type=int,
        help='Add a twin Y-axis and plot Y-columns starting from the given '
            'index value (count from 1) on the twin Y-axis',
        metavar='TWINIDX',
        default=None)

    # PLOT METADATA (say something about the data)
    parser.add_argument('-t', '--ptitle',
        action='store',
        help='Add title on the chart')

    parser.add_argument('-l', '--plabel',
        action='append',
        help='Label for each Y-column, provided in the same order. This goes '
            'into the legend. Use an empty string to skip it')

    parser.add_argument('-lt', '--ltitle',
        action='store',
        help='Title on the plot legend',
        default=None)

    parser.add_argument('-twlt', '--twinltitle',
        action='store',
        help='Title on the twin plot legend',
        default=None)

    parser.add_argument('-xl', '--xlabel',
        action='store',
        help='Custom label on the X-axis')

    parser.add_argument('-yl', '--ylabel',
        action='store',
        help='Custom label on the Y-axis')

    parser.add_argument('-tyl', '--tylabel',
        action='store',
        help='Custom Y-axis label for the twin Y-axis')

    parser.add_argument('--xstr',
        action='store_true',
        help='Treat X-column values as text, not numeric (applies to a bar plot)',
        default=False)

    parser.add_argument('-pd', '--pdfdata',
        action='store_true',
        help='Treat the provided data as PDF when generating a cdf chart',
        default=False)

    # PLOT ADD-ONS (give it a richer look)
    parser.add_argument('-xm', '--xmul',
        action='store',
        type=float,
        help='Custom X-axis multiplier constant (e.g., for unit conversion)',
        default=1)

    parser.add_argument('-ym', '--ymul',
        action='store',
        type=float,
        help='Custom Y-axis multiplier constant (e.g., for unit conversion)',
        default=1)

    parser.add_argument('-tym', '--tymul',
        action='store',
        type=float,
        help='Custom twin Y-axis multiplier constant (e.g., to change units)',
        default=1)

    parser.add_argument('-yn', '--ynorm',
        action='store_true',
        help='Normalize Y-column values relative to the first Y-column',
        default=False)

    parser.add_argument('--xlog',
        action='store_true',
        help='Plot X-axis on a log scale',
        default=False)

    parser.add_argument('--ylog',
        action='store_true',
        help='Plot Y-axis on a log scale',
        default=False)

    parser.add_argument('--tylog',
        action='store_true',
        help='Plot twin Y-axis on a log scale',
        default=False)

    parser.add_argument('-hl', '--hlines',
        action='store',
        type=float,
        nargs='*',
        help='Add horizontal lines at given Y-intercepts')

    parser.add_argument('-hlf', '--hlinesfile',
        action='store',
        help='File with (label,x-intercept) pairs for specifying horizontal '
            'lines with custom labels, one pair per line')

    parser.add_argument('-vl', '--vlines',
        action='store',
        type=float,
        nargs='*',
        help='Add vertical lines at given X-intercepts')

    parser.add_argument('-vlf', '--vlinesfile',
        action='store',
        help='Same as -hlf but for vertical lines')

    # PLOT COSMETICS (it's all about look and feel)
    parser.add_argument('-ls', '--linestyle',
        action='append',
        help='Custom line style for each plot, one per plot',
        type=LineStyle,
        choices=list(LineStyle))

    parser.add_argument('-bhs', '--barhatchstyle',
        action='append',
        help='Custom bar hatch style for each bar plot, one per plot',
        type=BarHatchStyle,
        choices=list(BarHatchStyle))

    parser.add_argument('-bs', '--stacknextbar',
        action='append',
        help='If specified and equals to 1, stack the next Y-column (bar chart)'
            ' on top of the previous one. When 0 or not specified, bars are'
            ' placed next to each other.',
        type=int,
        choices=[0,1])

    parser.add_argument('-cmi', '--colormarkerincr',
        action='append',
        help='If specified, this gives control over whether color/marker styles'
            'are changed as each Y-column is plotted. If 1, move to the next '
            'color/marker pair, or stay put if 0. If not specified, the pair'
            'will be changed for each Y-column plotted.',
        type=int,
        choices=[0,1])

    parser.add_argument('-li', '--labelincr',
        action='append',
        help='If specified, this helps with using same label for multiple plots'
            ' instead of specifying one per Y-column. The value indicates the'
            ' number of Y-columns to slide at/use a single label before moving'
            ' to the next label',
        type=int,
        choices=range(1,10),
        metavar='[1-10]')

    parser.add_argument('-nm', '--nomarker',
        action='store_true',
        help='Do not add markers on the chart data points',
        default=False)

    parser.add_argument('-fs', '--fontsize',
        action='store',
        type=int,
        help='Set font size of axis, legend and tick labels',
        default=15)

    parser.add_argument('-ll', '--legendloc',
        action='store',
        help='Custom legend location',
        type=LegendLoc,
        choices=list(LegendLoc),
        default=LegendLoc.BEST)

    parser.add_argument('-tll', '--twinlegendloc',
        action='store',
        help='Custom legend location for twin axis',
        type=LegendLoc,
        choices=list(LegendLoc),
        default=LegendLoc.BEST)

    parser.add_argument('-sz', '--size',
        nargs=2,
        action='store',
        metavar=('width', 'height'),
        type=float,
        help='Custom chart size, Takes two args: width height',
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
        help='Custom X-axis lower limit')

    parser.add_argument('--xmax',
        action='store',
        type=float,
        help='Custom X-axis upper limit')

    parser.add_argument('--ymax',
        action='store',
        type=float,
        help='Custom Y-axis upper limit')

    parser.add_argument('--tymin',
        action='store',
        type=float,
        help='Custom twin Y-axis lower limit')

    parser.add_argument('--tymax',
        action='store',
        type=float,
        help='Custom twin Y-axis upper limit')

    parser.add_argument('-nt', '--notail',
        action='store',
        help='Eliminate last x%% tail from CDF chart. Defaults to 1%%',
        nargs='?',
        type=float,
        const=0.1)

    parser.add_argument('-nh', '--nohead',
        action='store',
        help='Eliminate first x%% head from CDF chart. Defaults to 1%%',
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

    parser.add_argument('-s', '--show',
        action='store_true',
        help='Display the plot after saving it. Blocks the program.',
        default=False)

    return parser

def parser_get_plots(parser, args):
    """ Infer plots from arguments. Also, more paramter constraints that are too
    complex for argparse """

    # Constraints on Y-column data
    formats = 0
    formats += 1 if (args.dfileycolyerr is not None) else 0
    formats += 1 if (args.dfileycol is not None) else 0
    formats += 1 if (args.datafile is not None and args.ycolumn is not None) else 0
    formats += 1 if (args.datafile is not None and args.ycolumnyerr is not None) else 0
    if formats != 1:
        parser.error('At least (and only) one of the (-d/-yc) or (-d/-yce) or '
            '(-dyc) or (-dyce) formats should be used to provide input data!')

    if (args.datafile or args.ycolumn) and \
        (args.datafile and len(args.datafile) > 1) and \
        (args.ycolumn and len(args.ycolumn) > 1):
        parser.error('If using (-d/-yc) format, only one of the -d or -yc '
            'params allow multiple values. Use -dyc format otherwise.')

    if (args.datafile or args.ycolumnyerr) and \
        (args.datafile and len(args.datafile) > 1) and \
        (args.ycolumnyerr and len(args.ycolumnyerr) > 1):
        parser.error('If using (-d/-yce) format, only one of the -d or -yce '
            'params allow multiple values. Use -dyc(e) format otherwise.')

    # Constraints on X-column data
    xdatafile = None
    xcolumn = None
    if args.xcolumn is not None:
        xcolumn = args.xcolumn
    if args.dfilexcol is not None:
        if xcolumn:
            parser.error("Use either the -dxcol or -xcol to specify X-data, not both!")
        xdatafile = args.dfilexcol[0]
        xcolumn = args.dfilexcol[1]

    # Infer Y-column data
    plots = []
    if args.dfileycolyerr is not None:
        for (dfile, ycol, yerr) in args.dfileycolyerr:
            plots.append(Plot(dfile, ycol, yerr, xdatafile, xcolumn))
    elif args.dfileycol is not None:
        for (dfile, ycol) in args.dfileycol:
            plots.append(Plot(dfile, ycol, None, xdatafile, xcolumn))
    else:
        for dfile in args.datafile:
            if args.ycolumn is not None:
                for ycol in args.ycolumn:
                    plots.append(Plot(dfile, ycol, None, xdatafile, xcolumn))
            elif args.ycolumnyerr is not None:
                for (ycol, yerr) in args.ycolumnyerr:
                    plots.append(Plot(dfile, ycol, yerr, xdatafile, xcolumn))

    if len(plots) == 0:
        parser.error("Couldn't infer any plots from CLI arguments")

    # Infer twin plots
    if args.twin:
        if args.twin < 0 or args.twin > len(plots):
            parser.error("Invalid twin index, allowed [0, {})".format(len(plots)))
        for i, plot in enumerate(plots):
            plot.is_twin = (i+1) > args.twin

    # Infer labels
    if not args.labelincr:
        if args.plabel and len(args.plabel) != len(plots):
            parser.error("If plot labels are provided and --labelincr is not, "
                "labels must be provided for each plot and in the same order")
        if args.plabel:
            for i, label in enumerate(args.plabel):
                plots[i].label = label
    else:
        if not args.plabel:
            parser.error("If --labelincr is specified, plot labels must be "
                "specified with -l/--plabel")
        if len(args.plabel) < sum(args.labelincr):
            parser.error("If plot labels and --labelincr are provided, sum of "
                "label increments should not cross the number of plot labels")
        plotidx = 0
        labelidx = 0
        for incr in args.labelincr:
            for i in incr:
                plots[plotidx].label = args.plabel[labelidx]
                plotidx += 1
            labelidx += 1

    # Other constraints
    if (args.nohead or args.notail) and args.ptype != PlotType.CDF:
        parser.error("head and tail trimming is only supported for CDF plots "
            "(-z/--ptype: cdf)")

    if args.stacknextbar is not None and len(args.stacknextbar) != len(plots):
        parser.error("If --stacknextbar is provided, it must be provided for "
            "each plot and in the same order")
    return plots

def main():
    """ Main workflow """
    parser = parser_definition()
    args = parser.parse_args()
    plots = parser_get_plots(parser, args)

    # Create Matlplotlib figure
    matplotlib.rc('font', **{'family': 'sans-serif', 'size': args.fontsize})
    matplotlib.rc('figure', autolayout=True)
    matplotlib.rcParams['pdf.fonttype'] = 42  # recommended for latex-embeds
    fig, axmain = plt.subplots(1, 1, figsize=tuple(args.size))
    if args.ptitle:
        fig.suptitle(args.ptitle, x=0.3, y=0.9,
            horizontalalignment='left', verticalalignment='top')
        fig.tight_layout()

    # Add twin axes if necessary
    axtwin = None
    if args.twin:
        axtwin = axmain.twinx()
        # TODO: set the twin axis to the same color as the first twin plot
        # axes.spines['right'].set_color(COLORS[cidx])
        # axes.tick_params(axis='y', COLORS=COLORS[cidx])
        # axes.yaxis.label.set_color(COLORS[cidx])

    # Loop params init
    cidx = 0
    midx = 0
    base_dataset = None
    temp_xcol = None
    total_width = 0

    # Add plots one by one
    for plot_num, plot in enumerate(plots):
        axes = axtwin if plot.is_twin else axmain
        assert axes is not None, "invalid axes"

        # Get data
        xcol = plot.read_xcolumn()
        ycol = plot.read_ycolumn()
        if xcol is None:    xcol = ycol.index
        yerr = plot.read_yerror()
        ymul = args.tymul if plot.is_twin else args.ymul

        # Plot types
        if args.ptype == PlotType.LINE:
            xcol = [x * args.xmul for x in xcol]
            ycol = [y * ymul for y in ycol]
            yerr = [y * ymul for y in yerr] if yerr is not None else None

            if args.ynorm:
                if plot_num == 0:
                    base_dataset = ycol
                    ycol = [1 for _ in ycol]
                else:
                    ycol = [i/j for i,j in zip(ycol, base_dataset)]

            if args.xstr:   xcol = [str(x) for x in xcol]
            axes.errorbar(xcol, ycol, yerr=yerr, label=plot.label,
                color=COLORS[cidx],
                marker=(None if args.nomarker else MARKERS[midx]),
                markerfacecolor=(None if args.nomarker else COLORS[cidx]),
                ls=args.linestyle[plot_num].as_tuple() \
                    if args.linestyle is not None else None)
            # if args.xstr:   ax.set_xticks(xc)
            # if args.xstr:   ax.set_xticklabels(xc, rotation='45')

        elif args.ptype == PlotType.SCATTER:
            xcol = [x * args.xmul for x in xcol]
            ycol = [y * ymul for y in ycol]
            marker_size = 2*(72./fig.dpi)**2 if len(ycol) > 1000 else None
            axes.scatter(xcol, ycol, label=plot.label, color=COLORS[cidx],
                marker=(None if args.nomarker else MARKERS[midx]), s=marker_size)
            if args.xstr:   axes.set_xticks(xcol)
            if args.xstr:   axes.set_xticklabels(xcol, rotation='45')

        elif args.ptype == PlotType.BAR:
            xstart = np.arange(len(xcol)) * (len(plots) + 1) * args.barwidth
            if temp_xcol is None:  temp_xcol = xstart
            xcol = [x * args.xmul for x in xcol]
            ycol = [y * ymul for y in ycol]
            yerr = [y * ymul for y in yerr] if yerr is not None else None

            axes.bar(temp_xcol, ycol, yerr=yerr, width=args.barwidth,
                bottom=base_dataset, label=plot.label, color=COLORS[cidx],
                hatch=str(args.barhatchstyle[plot_num]) \
                    if args.barhatchstyle is not None else None)
            # ax.set_xticklabels(xcol, rotation='15' if args.xstr else 0)

            if args.stacknextbar and args.stacknextbar[plot_num] == 1:
                if base_dataset is None:    base_dataset = ycol
                else:   base_dataset = [a + b for a, b in zip(base_dataset, ycol)]
            else:
                base_dataset = None
                temp_xcol = temp_xcol + args.barwidth
                total_width += args.barwidth

            if plot_num == len(plots) - 1:
                xticks = xstart + total_width / 2
                axes.set_xticks(xticks)
                axes.set_xticklabels(xcol)

        elif args.ptype == PlotType.CDF:
            if args.pdfdata:
                # xcol remains the same
                ycol = np.cumsum(ycol)/sum(ycol)
            else:
                xcol = np.sort(ycol)
                ycol = 1. * np.arange(len(ycol)) / (len(ycol) - 1)

            # See if head and/or tail needs trimming
            # NOTE: We don't remove values, instead we limit the axes. This is
            # essentially zooming in on a CDF when the head or tail is too long
            head = None
            tail = None
            if args.nohead:
                for i, val in enumerate(ycol):
                    if val <= args.nohead/100.0:
                        head = xcol[i]
                if head:
                    args.xmin = head if args.xmin is None else min(head, args.xmin)
            if args.notail:
                for i, val in enumerate(ycol):
                    if val > (100.0 - args.notail)/100.0:
                        tail = xcol[i]
                        break
                if tail:
                    args.xmax = tail if args.xmax is None else max(tail, args.xmax)

            xcol = [x * args.xmul for x in xcol]
            ycol = [y * ymul for y in ycol]
            axes.step(xcol, ycol, label=plot.label, color=COLORS[cidx],
                where="post", marker=(None if args.nomarker else MARKERS[midx]),
                ls=args.linestyle[plot_num] if args.linestyle is not None else None)
                # markerfacecolor=(None if args.nomarker else COLORS[cidx]))

        else:
            raise Exception("chart type not supported")

        # Decide color and marker for the next plot
        if args.colormarkerincr:
            cidx = (cidx + args.colormarkerincr[plot_num]) % len(COLORS)
            midx = (midx + args.colormarkerincr[plot_num]) % len(MARKERS)
        else:
            cidx = (cidx + 1) % len(COLORS)
            midx = (midx + 1) % len(MARKERS)


    # Set x-axis params
    xlabel = args.xlabel if args.xlabel else plots[0].xcolumn
    axmain.set_xlabel(xlabel)
    if args.xmin is not None:   axmain.set_xlim(xmin=args.xmin)
    if args.xmax is not None:   axmain.set_xlim(xmax=args.xmax)
    if args.xlog:               axmain.set_xscale('log', basex=10)

    # Set y-axis params
    ylabel = args.ylabel if args.ylabel else plots[0].ycolumn
    axmain.set_ylabel(ylabel)
    if args.ymin is not None:   axmain.set_ylim(ymin=args.ymin)
    if args.ymax is not None:   axmain.set_ylim(ymax=args.ymax)
    if args.ylog:               axmain.set_yscale('log')

    # Set twin y-axis params
    if axtwin:
        tylabel = args.ylabel if args.ylabel else plots[args.axtwin].ycolumn
        axtwin.set_ylabel(tylabel)
        if args.tymin is not None:   axtwin.set_ylim(ymin=args.tymin)
        if args.tymax is not None:   axtwin.set_ylim(ymax=args.tymax)

    # Set main legend (skip a label if empty/whitespace text)
    lns, labels = axmain.get_legend_handles_labels()
    labels_new = [l for l in labels if not l.isspace()]
    lns_new = [l for i,l in enumerate(lns) if not labels[i].isspace()]
    args.legendloc.add_legend(axes, lns_new, labels_new, args.ltitle)

    # Set twin legend (skip a label if empty/whitespace text)
    if axtwin:
        lns, labels = axtwin.get_legend_handles_labels()
        labels_new = [l for l in labels if not l.isspace()]
        lns_new = [l for i,l in enumerate(lns) if not labels[i].isspace()]
        args.twinlegendloc.add_legend(axes, lns_new, labels_new, args.twinltitle)

    # Add any horizontal lines (only supported for main axes now)
    hlines = []
    if args.hlines:
        hlines += [(h, str(h)) for h in args.hlines]
    if args.hlinesfile and os.path.exists(args.hlinesfile):
        with open(args.hlinesfile) as f:
            for line in f.readlines():
                label = line.split(",")[0]
                intercept = int(line.split(",")[1])
                hlines.append((intercept, label))
    for (intercept, label) in hlines:
        plt.axhline(y=intercept, ls='dashed')
        plt.text(0.5, intercept, label, color='black', fontsize='small',
            transform=axmain.get_yaxis_transform(), rotation='horizontal')

    # Add any vertical lines
    vlines = []
    if args.vlines:
        vlines += [(v, str(v)) for v in args.vlines]
    if args.vlinesfile and os.path.exists(args.vlinesfile):
        with open(args.vlinesfile) as f:
            for line in f.readlines():
                label = line.split(",")[0]
                intercept = int(line.split(",")[1])
                vlines.append((intercept, label))
    for (intercept, label) in vlines:
        plt.axvline(x=intercept, ls='dashed')
        plt.text(intercept, 0.3, label, color='black', fontsize='small',
            transform=axmain.get_xaxis_transform(), rotation='vertical')

    # Save chart
    plt.savefig(args.output, format=str(args.outformat))
    if args.show:
        plt.show()

if __name__ == '__main__':
    main()
