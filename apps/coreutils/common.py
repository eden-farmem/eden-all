from defs import ROOT, ROOT_OUTPUT, ROOT_EDEN
import os
import subprocess

def read_conf_from_init_sh(p = "{}/coreutils/tests/init.sh".format(ROOT)):
    with open(p) as f:
        for l in f:
            l = l.strip()
            if "FLTRACE_LOCAL_MEMORY_MB" in l and not l.startswith("#"):
                i = l.index("#")
                l = l[:i]
                lm = l.split("=")[-1].strip().replace('"',"").replace("=","")
                unit  = "mb"
                break
            if "FLTRACE_LOCAL_MEMORY_BYTES" in l and not l.startswith("#"):
                i = l.index("#")
                l = l[:i]
                lm = l.split("=")[-1].strip().replace('"',"").replace("=","")
                unit  = "b"
                #print("lm:", lm)
                break
        else:
            raise  Exception("Not LM in init.sh")
    return lm, unit


def read_default_lm_bytes_from_trace_sh():
    with open(ROOT+"trace.sh") as f:
        for line in f:
            line = line.strip()
            if "FLTRACE_LOCAL_MEMORY_BYTES" in line:
                default_lm_bytes = int(line.split("=")[-1].split('"')[0].strip())
                break
        else:
            raise Exception("No FLTRACE_LOCAL_MEMORY_BYTES in trace sh")
    
    return default_lm_bytes


def no_next_execution(test_name, execution_number):
    default_lm_bytes = read_default_lm_bytes_from_trace_sh()
    dir_max_lm = os.path.join(ROOT_OUTPUT, test_name+"-lm{}{}".format(default_lm_bytes,"b"))
    dir_max_lm_raw = os.path.join(dir_max_lm, "raw")

    
    
    if type(execution_number) == str:
        execution_number_minus_1 = int(execution_number) - 1
    else:
        execution_number_minus_1 = execution_number - 1
    
    dir_max_lm_raw_execution_number =  os.path.join(dir_max_lm_raw, str(execution_number).zfill(3))
    dir_max_lm_raw_execution_number_minus_one =  os.path.join(dir_max_lm_raw, str(execution_number_minus_1).zfill(3))
    
    if os.path.exists(dir_max_lm_raw_execution_number_minus_one) and os.path.exists(dir_max_lm_raw_execution_number):
        return False

    return True

def compute_memory_usage_with_percent(test_name, execution_number, percent, debug = False):
    default_lm_bytes = read_default_lm_bytes_from_trace_sh()
    # read max from directory
    dir_max_lm = os.path.join(ROOT_OUTPUT, test_name+"-lm{}{}".format(default_lm_bytes,"b"))
    dir_max_lm_raw = os.path.join(dir_max_lm, "raw")
    dir_max_lm_raw_execution_number =  os.path.join(dir_max_lm_raw, str(execution_number).zfill(3))
    
    fs = os.listdir(dir_max_lm_raw_execution_number)
    for f in fs:
        if "fault-stats" in f:
            f_stat_name = f
            break
    else:
        raise Exception('Not Fault Stats')
    
    

    full_path_max_lm_raw_execution_number = os.path.join(dir_max_lm_raw_execution_number, f_stat_name)
    if debug:
        print("[common/compute_memory_usage_with_percent] Full path to max lm: {}".format(full_path_max_lm_raw_execution_number))

    cmd_compute_max_lm = "python3 {}/scripts/parse_fltrace_stat.py --maxrss -i {}".format(ROOT_EDEN, full_path_max_lm_raw_execution_number)
    if debug:
        print("[common/compute_memory_usage_with_percent] Computing max lm with cmd: {}".format(cmd_compute_max_lm))
    
    p = subprocess.Popen(cmd_compute_max_lm, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate()
    max_mem = int(out.decode('utf-8'))
    percent_mem = int(max_mem * 1.00 * percent / 100 )
    if debug:
        print("[common/compute_memory_usage_with_percent] Max lm: {}b; {} Percent: {}b".format(max_mem, percent, percent_mem))
    
    return percent_mem
    
def get_execution_number_from_file(name):
    # Saves exe number from prev run
    fname = "{}-execution-number.txt".format(name)
    exist = os.path.exists(fname)
    if exist:
        with open(fname) as f:
            for line in f:
                 execution_number = int(line.strip()) + 1
                 break
    else:
        execution_number = 0
    
    with open(fname, "w") as f:
        f.write("{}\n".format(execution_number))

    return str(execution_number)

def read_next_execution_number_from_file(name):
    fname = "{}-execution-number.txt".format(name)
    exist = os.path.exists(fname)
    if exist:
        with open(fname) as f:
            for line in f:
                 execution_number = int(line.strip()) + 1
                 break
    else:
        execution_number = 0

    return str(execution_number + 1)
    

