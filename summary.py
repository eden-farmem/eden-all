
# usage: python summary.py <experiment directory>

import enum
import json
import os
import sys
from collections import defaultdict
import re
import argparse
import glob

NUMA_NODE = 1
DISPLAYED_RSTAT_FIELDS = ["parks", "p_rx_ooo", "p_reorder_time"]
KONA_FIELDS = ["n_faults_r", "n_faults_w", "n_net_page_in", "n_net_page_out", "malloc_size", "mem_pressure"]
KONA_FIELDS_ACCUMULATED = ["n_faults_r", "n_faults_w", "n_net_page_in", "n_net_page_out", "n_faults"]

def percentile(latd, target):
    # latd: ({microseconds: count}, number_dropped)
    # target: percentile target, ie 0.99
    latd, dropped = latd
    count = sum([latd[k] for k in latd]) + dropped
    target_idx = int(float(count) * target)
    curIdx = 0
    for k in sorted(latd.keys()):
        curIdx += latd[k]
        if curIdx >= target_idx:
            return k
    return float("inf")

def read_lat_line(line):
    #line = line.split(" ", 1)[1]
    if line.startswith("Latencies: "):
        line = line[len("Latencies: "):]
    d = {}
    for l in line.strip().split():
        micros, count = l.split(":")
        d[int(micros)] = int(count)
    return d

def read_trace_line(line):
    if line.startswith("Trace: "):
        line = line[len("Trace: "):]
    points = []
    lats = defaultdict(int)
    for l in line.strip().split():
        start, delay, latency = l.split(":")
        if latency != "-1":
            lats[int(latency) // 1000] += 1
        if delay != "-1":
            points.append((int(start), int(latency)))
    return lats, points


# list_of_tuples: [({microseconds: count}, number_dropped)...]
def merge_lat(list_of_tuples):
    dropped = 0
    c = defaultdict(int)
    for s in list_of_tuples:
        for k in s[0]:
            c[k] += s[0][k]
        dropped += s[1]
    return c, dropped


def parse_loadgen_output(filename):
    with open(filename) as f:
        dat = f.read()

    samples = []
    line_starts = ["Latencies: ", "Trace: ", "zero, ","exponential, ",
                   "bimodal1, ", "constant, "]

    def get_line_start(line):
        for l in line_starts:
            # if line.startswith(l): return l
            if l in line:   return l
        return None

    """Distribution, Target, Actual, Dropped, Never Sent, Median, 90th, 99th, 99.9th, 99.99th, Start"""
    header_line = None
    for line in dat.splitlines():
	#line = line.split(" ", 1)[1]
        line_start = get_line_start(line)
        if not line_start: continue
        if not line.startswith(line_start): line = line[line.find(line_start):]
        if line_start == "Latencies: ":
            samples.append({
                'distribution': header_line[0],
                'offered': int(header_line[1]),
                'achieved': int(header_line[2]),
                'missed': int(header_line[4]),
                'latencies': (read_lat_line(line), int(header_line[3])),
                'time': int(header_line[10]),
            })
        elif line_start == "Trace: ":
            lats, tracepoints = read_trace_line(line)
            samples.append({
                'distribution': header_line[0],
                'offered': int(header_line[1]),
                'achieved': int(header_line[2]),
                'missed': int(header_line[4]),
                'latencies': (lats, int(header_line[3])),
                'tracepoints': tracepoints,
                'time': int(header_line[10]),
            })
        else:
            # print(header_line)
            header_line = line.strip().split(", ")
            assert len(header_line) > 10 or len(header_line) == 6, line
            if len(header_line) == 6:
                 samples.append({
                 'distribution': header_line[0],
                 'offered': int(header_line[1]),
                 'achieved': 0,
                 'missed': int(header_line[4]),
                 'latencies': ({}, int(header_line[3])),
                 'time': int(header_line[5]),
            })
    if len(samples) == 0 and header_line:
        # If no latencies, just record xput
        samples.append({
            'distribution': header_line[0],
            'offered': int(header_line[1]),
            'achieved': int(header_line[2]),
            'missed': int(header_line[4]),
            'latencies': ({}, int(header_line[3])),
            'time': int(header_line[10]),
        })
    return samples


def merge_sample_sets(a, b):
    samples = []
    # print(len(a),len(b))
    for ea, eb in zip(a, b):
        assert set(ea.keys()) == set(eb.keys())
        assert ea['distribution'] == eb['distribution']
        # assert ea['app'] == eb['app']
        if abs(ea['time'] - eb['time']) >= 2:   print(ea['time'], eb['time'])
        assert abs(ea['time'] - eb['time']) < 2
        newexp = {
            'distribution': ea['distribution'],
            'offered': ea['offered'] + eb['offered'],
            'achieved': ea['achieved'] + eb['achieved'],
            'missed': ea['missed'] + eb['missed'],
            'latencies': merge_lat([ea['latencies'], eb['latencies']]),
            # 'app': ea['app'],
            'time': min(ea['time'], eb['time']),
        }
        if 'tracepoints' in ea:
            newexp['tracepoints'] = ea['tracepoints'] + eb['tracepoints']
        samples.append(newexp)
        assert set(ea.keys()) == set(newexp.keys())
    # print(len(samples))
    return samples

def except_none(func):
	def e(*args, **kwargs):
		try:
			return func(*args, **kwargs)
		except:
			return None
	return e

@except_none
def load_app_output(app, directory, first_sample_time):

    parse_bg_key = {
        'swaptions': ("Swaption per second: ", None),
        'x264': ("/512 frames, ", " fps"),
        'stress': ("fakework rate: ", None)
    }
    #fixme
    if app['app'] not in parse_bg_key.keys():
        return None

    filename = "{}/{}.out".format(directory, app['name'])
    assert os.access(filename, os.F_OK)
    with open(filename) as f:
        bgdata = f.read()

    token_l, token_r = parse_bg_key.get(app['app'])

    lines = filter(lambda l: token_l in l, bgdata.splitlines())
    lines = map(lambda l: l.split(" ", 1), lines)

    datapoints = []
    for timestamp, line in lines:
        rate = line
        if token_l:
            rate = rate.split(token_l)[1]
        if token_r:
            rate = rate.split(token_r)[0]
        datapoints.append((int(timestamp), float(rate)))

    # baseline from first ten entries:
    x = datapoints[1:11]

    baseline = None
    if all([l[0] < first_sample_time for l in x]):
        baseline = sum([l[1] for l in x]) / len(x)

    return {
        'recorded_baseline': baseline,
        'recorded_samples': datapoints
    }

def parse_kona_log(dirn, experiment):

    fname = "{dirn}/memcached.out".format(dirn=dirn, **experiment)
    with open(fname) as f:
        data = f.read().splitlines()

    header_list = ("counters,n_faults_r,n_faults_w,n_faults_wp,n_wp_rm_upgrade_write,n_"
    "wp_rm_fail,n_rw_fault_q,n_r_from_w_q,n_r_from_w_q_fail,n_madvise,n_"
    "page_dirty,n_wp_install_fail,n_cl_dirty_try,n_cl_dirty_success,n_"
    "flush_try,n_flush_success,n_madvise_try,n_poller_copy_fail,n_net_"
    "page_in,n_net_page_out,n_net_writes,n_net_write_comp,page_lifetime_"
    "sum,net_read_sum,n_zp_fail,n_uffd_wake,malloc_size,munmap_size,"
    "madvise_size,mem_pressure,n_kapi_fetch_succ").split(",")
    COL_IDX = {k: v for v, k in enumerate(header_list)}

    stats = defaultdict(list)
    for line in data:
        if "counters," in line:
            dats = line.split()
            time = int(dats[0])
            values = dats[1].split(",")
            assert len(values) == 31, "unexpected kona log format"
            if header_list[1] == values[1]:     continue    #header
            for c in KONA_FIELDS:  stats[c].append((time, int(values[COL_IDX[c]])))            
            stats['n_faults'].append((time, int(values[COL_IDX['n_faults_r']]) + int(values[COL_IDX['n_faults_w']])))
    print("Reading columns: " + str(stats.keys()))
    return dict(stats)

@except_none
def parse_utilization(dirn, experiment):
    fname = "{dirn}/mpstat.{server_hostname}.log".format(
        dirn=dirn, **experiment)
    try:
        with open(fname) as f:
            data = f.read().splitlines()
        int(data[0].split()[0])
    except:
        return None

    cpuln = next(l for l in data if "_x86_64_" in l)
    ncpu = int(re.match(".*\((\d+) CPU.*", cpuln).group(1))
    headerln = next(l for l in data if "iowait" in l).split()
    # assume max 2 nodes
    assert "CPU" in headerln or "NODE" in headerln

    cols = {h: pos for pos, h in enumerate(headerln)}
    data = map(lambda l: l.split(), data)
    data = filter(lambda l: "%iowait" not in l and len(l) > 1, data[4:])

    if "NODE" in headerln:
        data = filter(lambda l: int(l[cols['NODE']]) == NUMA_NODE, data)
    else:
        assert all(lambda l: l[cols['CPU']] == 'all', data)

# % usr 100.0 - %idle
    data = map(lambda l: (int(l[0]), 100. - float(l[-1])), data)
    if not "NODE" in headerln:
        data = map(lambda a, b: a, 2 * b, data)
    return data

def parse_iokernel_log(dirn, experiment):
    fname = "{dirn}/iokernel.{server_hostname}.log".format(
        dirn=dirn, **experiment)
    with open(fname) as f:
        data = f.read()
        int(data.split()[0])

    stats = defaultdict(list)
    data = data.split(" Stats:")[1:]
    for d in data:
        RX_P = None
        for line in d.strip().splitlines():
            if "eth stats for port" in line: continue
            dats = line.split()
            tm = int(dats[0])
            for stat_name, stat_val in zip(dats[1::2], dats[2::2]):
                stats[stat_name.replace(":", "")].append((tm, int(stat_val)))
                if stat_name == "RX_PULLED:": RX_P = float(stat_val)
                if stat_name == "BATCH_TOTAL:": stats['IOK_SATURATION'].append((tm, RX_P / float(stat_val)))
    return stats

def parse_runtime_log(app, dirn):
    if app['name'] != 'memcached':
        return None

    fname = "{dirn}/{name}.out".format(dirn=dirn, **app)
    with open(fname) as f:
        data = f.read().splitlines()

    pattern = ("(\d+).*STATS>reschedules:(\d+),sched_cycles:(\d+),program_cycles:(\d+),"
    "threads_stolen:(\d+),softirqs_stolen:(\d+),softirqs_local:(\d+),parks:(\d+),"
    "preemptions:(\d+),preemptions_stolen:(\d+),core_migrations:(\d+),rx_bytes:(\d+),"
    "rx_packets:(\d+),tx_bytes:(\d+),tx_packets:(\d+),drops:(\d+),rx_tcp_in_order:(\d+),"
    "rx_tcp_out_of_order:(\d+),rx_tcp_text_cycles:(\d+),cycles_per_us:(\d+)")

    stat_vec = defaultdict(list)
    oldts = None
    values_old = None
    for line in data:
        if "STATS>" not in line:    continue
        match = re.match(pattern, line)
        if match:
            assert len(match.groups()) == 20
            values = [int(match.group(i+1)) for i in range(20)]
            if not values_old:
                values_old = values
                continue        #ignore first value
            diff = [x - y for x, y in zip(values, values_old)] 
            values_old = values

            ts = int(values[0])
            if oldts and ts <= oldts:
                # HACK: ts with memcached is not attaching timestamps properly
                # some rows are getting older timestamps
                ts = oldts + 1
            oldts = ts

            reschedules = diff[1]
            sched_cycles = diff[2]
            program_cycles = diff[3]
            threads_stolen = diff[4]
            softirqs_stolen = diff[5]
            softirqs_local = diff[6]
            parks = diff[7]
            preemptions = diff[8]
            preemptions_stolen = diff[9]
            core_migrations = diff[10]
            rx_bytes = diff[11]
            rx_packets = diff[12]
            tx_bytes = diff[13]
            tx_packets = diff[14]
            drops = diff[15]
            rx_tcp_in_order = diff[16]
            rx_tcp_out_of_order = diff[17]
            rx_tcp_text_cycles = diff[18]
            cycles_per_us = values[19]
            # print(values)
            # print(diff)

            stat_vec['rescheds'].append((ts, reschedules))
            stat_vec['schedtimepct'].append((ts, sched_cycles / (sched_cycles + program_cycles) * 100 
                if (sched_cycles + program_cycles) else 0))
            stat_vec['localschedpct'].append((ts, (1 - threads_stolen / reschedules) * 100 if reschedules else 0))
            stat_vec['softirqs'].append((ts, softirqs_local + softirqs_stolen))
            stat_vec['stolenirqpct'].append((ts, (softirqs_stolen / (softirqs_local + softirqs_stolen)) * 100 
                if (softirqs_local + softirqs_stolen) else 0))
            stat_vec['cpupct'].append((ts, (sched_cycles + program_cycles) * 100 /(float(cycles_per_us) * 1000000)))
            stat_vec['parks'].append((ts, parks))
            stat_vec['migratedpct'].append((ts, core_migrations * 100 / parks if parks else 0))
            stat_vec['preempts'].append((ts, preemptions))
            stat_vec['stolenpct'].append((ts, preemptions_stolen))
            stat_vec['rxpkt'].append((ts, rx_packets))
            stat_vec['rxbytes'].append((ts, rx_bytes))
            stat_vec['txpkt'].append((ts, tx_packets))
            stat_vec['txbytes'].append((ts,tx_bytes ))
            stat_vec['drops'].append((ts, drops))
            stat_vec['p_rx_ooo'].append((ts, rx_tcp_out_of_order / (rx_tcp_in_order + rx_tcp_out_of_order) * 100
                if (rx_tcp_in_order + rx_tcp_out_of_order) else 0))
            stat_vec['p_reorder_time'].append((ts, rx_tcp_text_cycles / (sched_cycles + program_cycles) * 100
                if (sched_cycles + program_cycles) else 0))
            continue
        assert False, line
    return stat_vec

def extract_window_seq(datapoints, wct_start, duration_sec, accumulated=False):
    window_start = wct_start + int(duration_sec * 0.1)
    window_end = wct_start + int(duration_sec * 0.9)
    datapoints = filter(lambda l: l[0] >= window_start and l[0] <= window_end, datapoints)
    if accumulated and len(datapoints) > 0:
        return [(x[0], x[1] - datapoints[i - 1][1]) for i, x in enumerate(datapoints)][1:]
    return datapoints

def extract_window(datapoints, wct_start, duration_sec, accumulated=False):
    datapoints = extract_window_seq(datapoints, wct_start, duration_sec, accumulated)
    # Weight any gaps in reporting
    try:
        total = 0
        nsecs = 0
        for idx, (tm, rate) in enumerate(datapoints[1:]):
            nsec = tm - datapoints[idx][0]
            total += rate * nsec
            nsecs += nsec
        avgmids = total / nsecs
    except:
        avgmids = None
    return avgmids

def extract_window_diff(datapoints, wct_start, duration_sec):
    window_start = wct_start + int(duration_sec * 0.1)
    window_end = wct_start + int(duration_sec * 0.9)
    datapoints = filter(lambda l: l[0] >= window_start and l[0] <= window_end, datapoints)
    data = [v for k,v in datapoints]
    return max(data) - min(data)

def extract_window_max(datapoints, wct_start, duration_sec):
    window_start = wct_start + int(duration_sec * 0.1)
    window_end = wct_start + int(duration_sec * 0.9)
    datapoints = filter(lambda l: l[0] >= window_start and l[0] <= window_end, datapoints)
    data = [v for k,v in datapoints]
    return max(data)

def load_loadgen_results(experiment, dirname):
    insts = [i for host in experiment['clients'] for i in experiment['clients'][host]]
    apps = [a for host in experiment['apps'] for a in experiment['apps'][host]]

    if not insts:
        print(insts)
        insts = [i for i in apps if i.get('protocol') == 'synthetic'] # local synth;
        experiment['clients'][experiment['server_hostname']] = insts #[i for i in insts if i.get('protocol') == 'synthetic'] #experiment['apps'] #semicorrect
    for inst in insts: #host in experiment['clients']:
#       for inst in experiment['clients'][host]:
        filename = "{}/{}.out".format(dirname, inst['name'])
        assert os.access(filename, os.F_OK)
        print("Parsing " + filename)
        data = parse_loadgen_output(filename)
        # assert len(data) == inst['samples'], filename
        if inst['name'] != "localsynth":
            server_handle = inst['name'].split(".")[1] 
            app = next(app for app in apps if app['name'] == server_handle)
        else:
            app = inst #local
        if not 'loadgen' in app:
            app['loadgen'] = data
        else:
            app['loadgen'] = merge_sample_sets(app['loadgen'], data)
        # print(len(app["loadgen"]))

    for app in apps:
        if not 'loadgen' in app: continue
        for sample in app['loadgen']:
            latd = sample['latencies']
            sample['p50'] = percentile(latd, 0.5)
            sample['p90'] = percentile(latd, 0.9)
            sample['p99'] = percentile(latd, 0.99)
            sample['p999'] = percentile(latd, 0.999)
            sample['p9999'] = percentile(latd, 0.9999)
            # del sample['latencies']
            sample['app'] = app


def parse_dir(dirname):
    files = os.listdir(dirname)
    assert "config.json" in files
    with open(dirname + "/config.json") as f:
        experiment = json.loads(f.read())

    load_loadgen_results(experiment, dirname)

    apps = [a for host in experiment['apps'] for a in experiment['apps'][host]]
    start_time = min(sample['time'] for app in apps for sample in app.get('loadgen', []))

    for app in apps:
        app['output'] = load_app_output(app, dirname, start_time)
        app['rstat'] = parse_runtime_log(app, dirname)

    experiment['mpstat'] = parse_utilization(dirname, experiment)
    experiment['ioklog'] = parse_iokernel_log(dirname, experiment)
    experiment['konalog'] = parse_kona_log(dirname, experiment)
    return experiment


def arrange_2d_results(experiment):
    # per start time: the 1 background app of choice, aggregate throughtput,  
    # 1 line per start time per server application
    apps = [a for host in experiment['apps'] for a in experiment['apps'][host]]
    by_time_point = zip(*(app['loadgen'] for app in apps if 'loadgen' in app))
    bgs = [app for app in apps if app['output']]
    # TODO support multiple bg apps
    assert len(bgs) <= 1
    bg = bgs[0] if bgs else None

    runtime = experiment['clients'].itervalues().next()[0]['runtime']

    header1 = ["system", "app", "background", "transport", "spin", "nconns", "threads"]
    header2 = ["offered", "achieved", "p50", "p90", "p99", "p999", "p9999", "distribution"]
    header3 = ["tput", "baseline", "totaloffered", "totalachieved", "totalcpu"] #, "localcpu", "ioksaturation"]
    header4 = ["rfaults","wfaults", "tfaults", "netin", "netout","maxmem","maxpressure"]

    header = header1 + header2 + header3 + header4 + DISPLAYED_RSTAT_FIELDS
    lines = [header]
    ncons = 0
    for list_pm in experiment['clients'].itervalues():
        for i in list_pm: 
            ncons += i['client_threads']

    for time_point in by_time_point:
        times = set(t['time'] for t in time_point)
        #assert len(times) == 1 # all start times are the same
        time = times.pop()
        if len(times) == 1: assert abs(times.pop() - time) <= 1
        else:   assert len(times) == 0
        bgbaseline = bg['output']['recorded_baseline'] if bg else 0
        bgtput = extract_window(bg['output']['recorded_samples'], time, runtime) if bg else 0
        if bgtput is None:  bgtput = 0
        cpu = extract_window(experiment['mpstat'], time, runtime) if experiment['mpstat'] else None
        total_offered = sum(t['offered'] for t in time_point)
        total_achieved = sum(t['achieved'] for t in time_point)
        iok_saturation = extract_window(experiment['ioklog']['IOK_SATURATION'], time, runtime) if experiment['ioklog'] else None
        # Kona (header4) stuff
        rfaults = extract_window(experiment['konalog']['n_faults_r'], time, runtime, accumulated=True) if 'n_faults_r' in experiment['konalog'] else 0
        wfaults = extract_window(experiment['konalog']['n_faults_w'], time, runtime, accumulated=True) if 'n_faults_w' in experiment['konalog'] else 0
        tfaults = extract_window(experiment['konalog']['n_faults'], time, runtime, accumulated=True) if 'n_faults' in experiment['konalog'] else 0
        netin = extract_window(experiment['konalog']['n_net_page_in'], time, runtime, accumulated=True) if 'n_net_page_in' in experiment['konalog'] else 0
        netout = extract_window(experiment['konalog']['n_net_page_out'], time, runtime, accumulated=True) if 'n_net_page_out' in experiment['konalog'] else 0
        maxmem = extract_window_max(experiment['konalog']['malloc_size'], time, runtime) if 'malloc_size' in experiment['konalog'] else None
        maxpressure = extract_window(experiment['konalog']['mem_pressure'], time, runtime) if 'mem_pressure' in experiment['konalog'] else None

        for point in time_point:
            out = [experiment['system'], point['app']['app'], bg['app'] if bg else None, point['app'].get('transport', None), point['app']['spin'] > 1, ncons, point['app']['threads']]
            out += [point[k] for k in header2]
            out += [bgtput, bgbaseline, total_offered, total_achieved, cpu]
            out += [rfaults, wfaults, tfaults, netin, netout, maxmem, maxpressure]
            # header4
            """if point['app']['rstat']:
                out.append(extract_window(point['app']['rstat']['cpupct'], time, runtime))
            else:
                out.append(None)
            out.append(iok_saturation)"""
            for field in DISPLAYED_RSTAT_FIELDS:
                if point['app']['rstat']:
                    out.append(extract_window(point['app']['rstat'][field], time, runtime))
                else:
                    out.append(None)
            lines.append(out)
        for bgl in bgs:
            continue; out = [experiment['system'], bgl['app'], bg['app'] if bg else None, 
                    None, bgl['spin'] > 1]
            out += [0]*7 + [None]
            out.append(extract_window(bgl['output']['recorded_samples'], time, runtime))
            out.append(bgl['output']['recorded_baseline'])
            out += [total_offered, total_achieved, cpu]
            """if bgl['rstat']:
                out.append(extract_window(bgl['rstat']['cpupct'], time, runtime))
            else:
                out.append(None)
            out.append(iok_saturation)"""
            for field in DISPLAYED_RSTAT_FIELDS:
                if point['app']['rstat']:
                        out.append(extract_window(point['app']['rstat'][field], time, runtime))
                else:
                        out.append(None)
            lines.append(out)
    return lines


def rotate(output_lines):
    resdict = {}
    headers = output_lines[0]
    for i, h in enumerate(headers):
        resdict[h] = [l[i] for l in output_lines[1:]]
    return resdict


def print_res(res):
    for line in res:
        print(",".join([str(x) for x in line]))


def do_it_all(dirname, save_lat=False, save_kona=False, save_iok=False, save_rstat=False):
    exp = parse_dir(dirname)
    stats = arrange_2d_results(exp)
    bycol = rotate(stats)

    STAT_F = "{}/stats/".format(dirname)
    os.system("mkdir -p " + STAT_F)
    with open(STAT_F + "stat.csv", "w") as f:
        for line in stats:
            x = ",".join([str(x) for x in line])
            print(x)
            f.write(x + '\n')

    # Write latencies too
    if save_lat:
        apps = [a for host in exp['apps'] for a in exp['apps'][host]]
        for app in apps:
            if not 'loadgen' in app: continue
            for i, sample in enumerate(app['loadgen']):
                latfile = STAT_F + "latencies_{}".format(i)
                print("Writing latencies to " + latfile)
                with open(latfile, "w") as f:
                    f.write("Latencies\n")
                    for k,v in sample['latencies'][0].items():
                        f.writelines([str(k) + "\n"] * v)
                print(sample['offered'], sample['achieved'])

    if save_rstat:
        runtime = exp['clients'].itervalues().next()[0]['runtime']
        apps = [a for host in exp['apps'] for a in exp['apps'][host]]
        for app in apps:
            if not app['rstat']: continue
            if not 'loadgen' in app: continue
            for i, sample in enumerate(app['loadgen']):
                start = sample['time']
                # print(start, runtime)
                rstatfile = STAT_F + "rstat_{}_{}".format(app['name'], i)
                print("Writing runtime stats to " + rstatfile)
                with open(rstatfile, "w") as f:
                    trimmed = { k:extract_window_seq(v, start, runtime) for k,v in app['rstat'].items()}
                    # print(trimmed.keys())
                    f.write("time," + ",".join(trimmed.keys()) + "\n")
                    for i, (time, _) in enumerate(trimmed["rescheds"]):
                        values = [str(time - start)] + [str(trimmed[k][i][1]) for k in trimmed.keys()]
                        f.write(",".join(values) + "\n")
    
    if save_iok and exp['ioklog']:
        runtime = exp['clients'].itervalues().next()[0]['runtime']
        apps = [a for host in exp['apps'] for a in exp['apps'][host]]
        for app in apps:
            if not 'loadgen' in app: continue
            for i, sample in enumerate(app['loadgen']):
                start = sample['time']
                # print(start, runtime)
                iokfile = STAT_F + "iokstats_{}".format(i)
                print("Writing iok stats to " + iokfile)
                with open(iokfile, "w") as f:
                    trimmed = { k:extract_window_seq(v, start, runtime) for k,v in exp['ioklog'].items()}
                    # print(trimmed.keys())
                    f.write("time," + ",".join(trimmed.keys()) + "\n")
                    for i, (time, _) in enumerate(trimmed["RX_PULLED"]):
                        values = [str(time - start)] + [str(trimmed[k][i][1]) for k in trimmed.keys()]
                        f.write(",".join(values) + "\n")

    if save_kona and exp['konalog']:
        runtime = exp['clients'].itervalues().next()[0]['runtime']
        apps = [a for host in exp['apps'] for a in exp['apps'][host]]
        for app in apps:
            if not 'loadgen' in app: continue
            for i, sample in enumerate(app['loadgen']):
                start = sample['time']
                # print(start, runtime)
                konafile = STAT_F + "konastats_{}".format(i)
                print("Writing kona stats to " + konafile)
                with open(konafile, "w") as f:
                    # FIXME: Some columns might not be cumulative
                    trimmed = { k:extract_window_seq(v, start, runtime, accumulated=(k in KONA_FIELDS_ACCUMULATED)) 
                                for k,v in exp['konalog'].items()}
                    # print(trimmed)
                    f.write("time," + ",".join(trimmed.keys()) + "\n")
                    for i, (time, _) in enumerate(trimmed["n_faults_r"]):
                        values = [str(time - start)] + [str(trimmed[k][i][1]) for k in trimmed.keys()]
                        f.write(",".join(values) + "\n")

    return bycol


def main():
    parser = argparse.ArgumentParser("Summarizes exp results")
    parser.add_argument('-n', '--name', action='store', help='Exp (directory) name')
    parser.add_argument('-d', '--dir', action='store', help='Path to data dir', default="./data")
    parser.add_argument('-sl', '--lat', action='store_true', help='save latencies to file', default=False)
    parser.add_argument('-sk', '--kona', action='store_true', help='save kona stats to file', default=False)
    parser.add_argument('-si', '--iok', action='store_true', help='save iok stats to file', default=False)
    parser.add_argument('-sa', '--app', action='store_true', help='save app runtime stats to file', default=False)
    args = parser.parse_args()

    expname = args.name
    if not expname:  
        subfolders = glob.glob(args.dir + "/*/")
        latest = max(subfolders, key=os.path.getctime)
        expname = os.path.basename(os.path.split(latest)[0])
    dirname = os.path.join(args.dir, expname)

    print("Summarizing exp run: " + expname)
    do_it_all(dirname, save_lat=args.lat, save_kona=args.kona, 
        save_iok=args.iok, save_rstat=args.app)

if __name__ == '__main__':
    main()
