import os
import argparse
import shutil
import subprocess

from defs import *
from common import read_conf_from_init_sh

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

def main():
    if not os.path.exists(MERGE_SCRIPT):
        raise Exception("Path not exist: {}".format(MERGE_SCRIPT))
    if not os.path.exists(FAULT_ANALYSIS_SCRIPT):
        raise Exception("Path not exist: {}".format(FAULT_ANALYSIS_SCRIPT))
    if not os.path.exists(ROOT_OUTPUT):
        raise Exception("Path not exist: {}".format(ROOT_OUTPUT))

    
    
    

    parser = argparse.ArgumentParser(description='Arguments for insert env to init.sh')
    # add args
    parser.add_argument('--wd',  required=True, help="path to working directory")
    parser.add_argument('--name',  required=True, help="current test case name")
    parser.add_argument('-m', default="1", help='Local Mem')
    parser.add_argument('-d', action="store_true", help='Print Debug')
    parser.add_argument('--percent', default=0, type=int, help='percentage of max m')
    
    # so -r overwrites the serial number
    parser.add_argument('-r', default=None, type=int, help="execution serial number")
    
    args = parser.parse_args()

    
    debug = args.d

    execution_number_from_f = get_execution_number_from_file(args.name)
    execution_number = execution_number_from_f
    
    if args.r != None:
        execution_number = str(args.r)
    
    if debug:
        print("[in_folder_result_processing/main] ", "serial number from file: {}, r: {}".format(execution_number_from_f,args.r))
    
    if debug:
        print("[in_folder_result_processing/main] ", args, os.getcwd())

    # create directories
    if args.percent == 0:
        lm, unit = read_conf_from_init_sh()
        dirpath = os.path.join(ROOT_OUTPUT, args.name+"-lm{}{}".format(lm,unit))
    else:
        dirpath = os.path.join(ROOT_OUTPUT, args.name)


    if os.path.exists(dirpath) and os.path.isdir(dirpath):
        # shutil.rmtree(dirpath)
        pass
    if not os.path.exists(dirpath):
        os.mkdir(dirpath)
        if debug:
            print("[in_folder_result_processing/main] Creating Dir: {}".format(dirpath))

    f_analysis_path = os.path.join(dirpath, "fault_analysis")
    if os.path.exists(f_analysis_path) and os.path.isdir(f_analysis_path):
        # shutil.rmtree(dirpath)
        pass
    if not os.path.exists(f_analysis_path):
        os.mkdir(f_analysis_path)
        if debug:
            print("[in_folder_result_processing/main] Creating Dir: {}".format(f_analysis_path))

    # create sub dir under fault analysis
    f_analysis_current_execution = os.path.join(f_analysis_path, execution_number.zfill(3))
    if os.path.exists(f_analysis_current_execution) and os.path.isdir(f_analysis_current_execution):
        shutil.rmtree(f_analysis_current_execution)
    os.mkdir(f_analysis_current_execution)
    if debug:
        print("[in_folder_result_processing/main] Creating Dir: {}".format(f_analysis_current_execution))

    
    tracepath = os.path.join(dirpath, "traces")
    if os.path.exists(tracepath) and os.path.isdir(tracepath):
        # shutil.rmtree(tracepath)
        pass
    if not os.path.exists(tracepath):
        os.mkdir(tracepath)
        if debug:
            print("[in_folder_result_processing/main] Creating Dir: {}".format(tracepath))

    # create sub dir under tracepath
    tracepath_current_execution = os.path.join(tracepath, execution_number.zfill(3))
    if os.path.exists(tracepath_current_execution) and os.path.isdir(tracepath_current_execution):
        shutil.rmtree(tracepath_current_execution)
    os.mkdir(tracepath_current_execution)
    if debug:
        print("[in_folder_result_processing/main] Creating Dir: {}".format(tracepath_current_execution))

    rawpath = os.path.join(dirpath, "raw")
    if os.path.exists(rawpath) and os.path.isdir(rawpath):
        # shutil.rmtree(rawpath)
        pass
    if not os.path.exists(rawpath):
        os.mkdir(rawpath)
        if debug:
            print("[in_folder_result_processing/main] Creating Dir: {}".format(rawpath))

    # create sub dir under raw
    rawpath_current_execution = os.path.join(rawpath, execution_number.zfill(3))
    if os.path.exists(rawpath_current_execution) and os.path.isdir(rawpath_current_execution):
        shutil.rmtree(rawpath_current_execution)
    os.mkdir(rawpath_current_execution)
    if debug:
        print("[in_folder_result_processing/main] Creating Dir: {}".format(rawpath_current_execution))

    # move data to raw -- might have to be very specific
    curdir_files = os.listdir(args.wd)
    if debug:
        print("[in_folder_result_processing/main] Generated Files in CWD: {}".format(curdir_files))

    for f in curdir_files:
        if "fault-samples" in f:
            TRACE_NAME = f
            break
    else:
        raise Exception("Error: Not Traces in Dir: {}".format(args.wd, curdir_files))

    mv_cmd = "cd {}; mv fault* {}".format(args.wd, rawpath_current_execution)
    subprocess.call(mv_cmd, shell=True)
    if debug:
        print("[in_folder_result_processing/main] Moving traces to raw with cmd: {}".format(mv_cmd))
    
    # merging trace data
    RAW_TRACE_PATH = os.path.join(rawpath_current_execution, TRACE_NAME)
    PROCESSED_TRACE_PATH = os.path.join(tracepath_current_execution, "{}_000.txt".format(execution_number.zfill(3)))
    merge_cmd = "python3 {} -i {} -o {}".format(MERGE_SCRIPT, RAW_TRACE_PATH, PROCESSED_TRACE_PATH) 
    subprocess.call(merge_cmd, shell=True)
    if debug:
        print("[in_folder_result_processing/main] Merging Traces with cmd: {}".format(merge_cmd))

    # performing fault analysis 100
    f_analysis_100_cmd = "python3 {} -d {} -n {}_100 -c 100 -R -z".format(FAULT_ANALYSIS_SCRIPT, tracepath_current_execution, "{}-{}".format(args.name, execution_number.zfill(3))) 
    f_analysis_100_output_path = os.path.join(f_analysis_current_execution, "result.txt")

    with open(f_analysis_100_output_path, "w") as f_analysis_100_output_file:
        p = subprocess.Popen(f_analysis_100_cmd, shell=True, stdout=f_analysis_100_output_file, stderr=subprocess.PIPE)
        out, err = p.communicate()
    
    if debug:
        print("[in_folder_result_processing/main] Performing fault analysis (100) with cmd: {}; saved to: {}".format(f_analysis_100_cmd, f_analysis_100_output_path))
    
    if len(err.decode('utf-8')) != 0:
        raise Exception("Error: Performing fault analysis failed {}".format(err.decode('utf-8')))
        

    # performing fault analysis 95
    f_analysis_95_cmd = "python3 {} -d {} -n {}_95 -c 95 -r -z".format(FAULT_ANALYSIS_SCRIPT, tracepath_current_execution, "{}-{}".format(args.name, execution_number.zfill(3))) 
    f_analysis_95_output_path = os.path.join(f_analysis_current_execution, "result.txt")

    with open(f_analysis_95_output_path, "a") as f_analysis_95_output_file:
        p = subprocess.Popen(f_analysis_95_cmd, shell=True, stdout=f_analysis_95_output_file, stderr=subprocess.PIPE)
        out, err = p.communicate()
    
    if debug:
        print("[in_folder_result_processing/main] Performing fault analysis (95) with cmd: {}; saved to: {}".format(f_analysis_95_cmd, f_analysis_95_output_path))
    
    if len(err.decode('utf-8')) != 0:
        raise Exception("Error: Performing fault analysis failed {}".format(err.decode('utf-8')))
        

    # fault_analysis_tool="../../../../fault-analysis/analysis/trace_codebase.py"
    # results="${trace_dir}/results.txt"
    # python ${fault_analysis_tool} -d "$trace_dir/traces" -n "${folder_name}_100" -c 100 -R > $results
    # python ${fault_analysis_tool} -d "$trace_dir/traces" -n "${folder_name}_95" -c 95 -r >> $results
    # cat $results


if __name__ == "__main__":
    main()