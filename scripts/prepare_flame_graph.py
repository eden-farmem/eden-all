#
# Build flame graph format from stack traces
#

import argparse
import csv
import os
import re

## Exclude these file sections from the flame graph
# E.g., to avoid recursive stacks. Hard-coding for now.
EXCLUDED_SECTIONS = {
    "qsort_custom.c": [(62, 71)],       #  sort recursive
}

## Exclude traces with these file sections from the flame graph
EXCLUDED_TRACES = {
    "assoc.c": [(211, 213)],            # memcached hash expand
    "items.c": [
        (959, 959),                     # memcached refcount wp
        (481, 481),                     # memcached set path lru                
    ],
    "main.c": [(334, 334)],             # synthetic zipf                
    "zipf.c": [(0, 5000)],              # synthetic zipf                
}

### Definitions
class CodeFile:
    """Source code file"""
    def __init__(self, dirpath, name, local):
        self.dirpath = dirpath
        self.name = name
        self.local = local

    def __str__(self):
        dirpath = self.dirpath + "/" if self.dirpath else ""
        return "{}{}".format(dirpath, self.name)

    def __eq__(self, other):
        return self.dirpath == other.dirpath and self.name == other.name


class CodePointer:
    """Pointer to a code location"""

    def __init__(self, ip):
        self.ip = ip
        self.tcount = 0     # unique traces containing this ip
        self.fcount = 0     # number of faults at this ip
        self.ops = set()    # ops seen at this code pointer

        # fill these once
        self.file = None
        self.line = None
        self.pd = None      # path discriminator
        self.lib = None
        self.inlineparents = []  # parent code pointers if inlined
        self.originalcp = None    # original code pointer if inlined

    def add_code_location(self, text, srcdir=None):
        """Fill the code location details parsed from a string"""
        # expected format: <filepath>:<line> (discriminator <pd>)
        local = False
        pattern = r"([^:]*):([0-9?]+)\s*(\(discriminator ([0-9]+)\))*"
        match = re.fullmatch(pattern, text)
        assert match and len(match.groups()) == 4
        filepath = match.groups()[0]
        if srcdir and filepath.startswith(srcdir):
            filepath = filepath[len(srcdir):].strip("/")
            local = True
        filename = filepath.split("/")[-1]
        dirpath = filepath[:-len(filename)].rstrip("/")
        file = CodeFile(dirpath, filename, local)
        line = match.groups()[1]
        if "?" in line:     line = 0
        self.file = file
        self.line = int(line)
        self.pd = match.groups()[3] if match.groups()[3] else None

    def flamegraph_name(self, leaf=False):
        """ customized name for the flame graph viz. """
        prefix = os.path.basename(self.lib) if self.lib else "Unknown"
        filename = os.path.basename(self.file.name) if self.file else None
        suffix = "{}:{}".format(filename, self.line) if filename else self.ip
        s = "{}|{}".format(prefix, suffix)
        if self.pd:   s += " ({})".format(self.pd)
        # add suffix for coloring
        if leaf:
            originalcp = self.originalcp if self.originalcp else self
            if len(originalcp.ops) == 1:
                op = list(originalcp.ops)[0]
                if op == "read":            s += "[r]"
                elif op == "wrprotect":     s += "[p]"
                elif op == "write":         s += "[w]"
            elif "read" not in originalcp.ops:    s += "[w]"
        return s

    def ignore(self):
        """Ignore this code pointer when writing to the flame graph"""
        ignore = False
        if self.file and self.line: 
            if self.file.name in EXCLUDED_SECTIONS:
                for (start, end) in EXCLUDED_SECTIONS[self.file.name]:
                    if start <= self.line <= end:
                        ignore = True
                        break
        return ignore

    def ignore_trace(self):
        """Ignore traces with this code pointer when writing to the flame graph"""
        ignore = False
        if self.file and self.line: 
            if self.file.name in EXCLUDED_TRACES:
                for (start, end) in EXCLUDED_TRACES[self.file.name]:
                    if start <= self.line <= end:
                        ignore = True
                        break
        return ignore

    def __eq__(self, other):
        return self.ip == other.ip


class CodeLink:
    """(Directed) Link between two code pointers"""

    def __init__(self, left, right):
        self.lip = left
        self.rip = right
        self.tcount = 0     # unique traces containing this link
        self.fcount = 0     # number of faults with this link

    def __str__(self):
        return "{} -> {}".format(self.lip, self.rip)

    def __eq__(self, other):
        return self.lip == other.lip and self.rip == other.rip


class Fault:
    """Fault info for a single fault"""
    trace = None            # stack trace, list of ips
    count = None
    op = None
    type = None

    def __eq__(self, other):
        return "|".join(self.trace) == "|".join(other.trace)


class FaultTraces:
    """Fault traces for a single run"""
    runid = None
    faults = None           # list of faults
    codepointers = None     # map from ip to code pointers
    codelinks = None        # map from code pointer to code pointers
    files = None            # set of all known source files
    sigips = None           # ips that fall in the signal handler
    libs = None             # set of all known libraries

    def __init__(self):
        self.faults = []
        self.codepointers = {}
        self.codelinks = {}
        self.files = set()
        self.libs = set()


def parse_fault_from_csv_row(ftraces, row, srcdir=None):
    """Parse fault info from a row the csv trace file"""
    fault = Fault()
    fault.trace = row["ips"].split("|")
    fault.count = int(row["count"])
    fault.op = row["op"]
    fault.type = row["type"]
    ftraces.faults.append(fault)

    # parse libs if available
    libs = [None] * len(fault.trace)
    if "lib" in row:
        libs = row["lib"].split("<//>")
        assert(len(libs) == len(fault.trace))
        ftraces.libs.update(libs)

    # add code locations
    previp = None
    codes = row["code"].split("<//>")
    assert len(codes) == len(fault.trace)
    for ip, code, lib in zip(fault.trace, codes, libs):
        if not ip:
            continue

        # add code pointer
        if ip not in ftraces.codepointers:
            ftraces.codepointers[ip] = CodePointer(ip)
        codepointer = ftraces.codepointers[ip]

        # parse and save location information
        if codepointer.file is None:
            if code and "??" not in code:
                # main code location
                mcode = code.split("<<<")[0]
                codepointer.add_code_location(mcode, srcdir)
                ftraces.files.add(str(codepointer.file))
                # inlined locations
                inlinedcodes = code.split("<<<")[1:]
                for icode in inlinedcodes:
                    if icode and "??" not in icode:
                        # do not add these to global maps
                        inlinedpointer = CodePointer(ip)
                        inlinedpointer.add_code_location(icode, srcdir)
                        inlinedpointer.originalcp = codepointer
                        inlinedpointer.lib = lib
                        ftraces.files.add(str(inlinedpointer.file))
                        codepointer.inlineparents.append(inlinedpointer)
            codepointer.lib = lib

        codepointer.tcount += 1
        codepointer.fcount += fault.count
        codepointer.ops.add(fault.op)
        ftraces.codepointers[ip] = codepointer

        # save code link
        if previp:
            if (previp, ip) not in ftraces.codelinks:
                ftraces.codelinks[(previp, ip)] = CodeLink(previp, ip)
            codelink = ftraces.codelinks[(previp, ip)]
            codelink.tcount += 1
            codelink.fcount += fault.count
        previp = ip

    # delete ips that fall in the signal handler and check
    # that they are the same in all traces
    IPS_IN_SIGNAL_HANDLER = 2
    sigips = []
    for _ in range(IPS_IN_SIGNAL_HANDLER):
        sigips.append(fault.trace.pop(0))
    assert ftraces.sigips is None or sigips == ftraces.sigips
    ftraces.sigips = sigips

    # reverse the trace (we get it in bottom-up order)
    if "" in fault.trace:
        fault.trace.remove("")
    fault.trace.reverse()

### Main

def main():
    # parse args
    parser = argparse.ArgumentParser("Build fault graph from trace files")
    parser.add_argument('-i', '--input', action='store', nargs='+', help="path to the input trace file(s)", required=True)
    parser.add_argument('-s', '--srcdir', action='store', help='base path to the app source code', default="")
    parser.add_argument('-c', '--cutoff', action='store', type=int, help='pruning cutoff as percentage of total fault count')
    parser.add_argument('-z', '--zero', action='store_true', help='consider only zero faults', default=False)
    parser.add_argument('-o', '--output', action='store', help='path to the output flame graph data', required=True)
    args = parser.parse_args()

    # read in
    traces = FaultTraces()
    for file in args.input:
        with open(file) as csvfile:
            csvreader = csv.DictReader(csvfile)
            for row in csvreader:
                parse_fault_from_csv_row(traces, row, args.srcdir)

    # print some info
    print("Unique Traces: {}".format(len(traces.faults)))
    print("Unique code locations: {}".format(len(traces.codepointers)))
    knowncps = [cp for cp in traces.codepointers.values() if cp.file is not None]
    print("Known code locations: {}".format(len(knowncps)))
    print("Total source files: {}".format(len(traces.files)))

    # filter for zero faults
    if args.zero:
        traces.faults = [f for f in traces.faults if f.type == "zero"]
    else:
        traces.faults = [f for f in traces.faults if f.type != "zero"]

    # prune traces (simplest way to prune: remove all traces below 
    # a certain fault count)
    if args.cutoff:
        traces.faults.sort(key=lambda f: f.count, reverse=True)
        fsum = sum([f.count for f in traces.faults])
        cutoff = fsum * args.cutoff / 100
        fsum = 0
        cutoffidx = len(traces.faults)
        for i, f in enumerate(traces.faults):
            fsum += f.count
            if fsum >= cutoff:
                cutoffidx = i
                break
        traces.faults = traces.faults[:cutoffidx]
        print("Unique {}% Traces: {}".format(args.cutoff, len(traces.faults)))

    # return in flamegraph format
    with open(args.output, "w") as fp:
        for f in traces.faults:
            locations = []
            ignore = False
            for i, ip in enumerate(f.trace):
                cp = traces.codepointers[ip]
                if cp.ignore_trace():
                    ignore = True
                    break
                if cp.ignore():
                    continue
                locations += [c.flamegraph_name() for c in reversed(cp.inlineparents)]
                locations.append(cp.flamegraph_name(i == len(f.trace)-1))
            tracestr = ";".join(locations)
            if not ignore:
                fp.write("{} {}\n".format(tracestr, f.count))
        print("Wrote {} traces to {}".format(len(traces.faults), args.output))


if __name__ == "__main__":
    main()