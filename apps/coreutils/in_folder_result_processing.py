import os
import argparse
import shutil
import subprocess

MERGE_SCRIPT = "/home/e7liu/eden-all/scripts/parse_fltrace_samples.py"
FAULT_ANALYSIS_SCRIPT = "/home/e7liu/eden-all/fault-analysis/analysis/trace_codebase.py"
ROOT_OUTPUT="/home/e7liu/eden-all/apps/coreutils/coreutils_output"

def main():
    ROOT_OUTPUT
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
    parser.add_argument('-r', default=0, help="execution serial number")
    parser.add_argument('-d', action="store_true", help='Print Debug')
    args = parser.parse_args()
    
    execution_number = str(args.r)
    debug = args.d
    
    if debug:
        print(args, os.getcwd())

    # create directories
    dirpath = os.path.join(ROOT_OUTPUT, args.name)
    if os.path.exists(dirpath) and os.path.isdir(dirpath):
        # shutil.rmtree(dirpath)
        pass
    if not os.path.exists(dirpath):
        os.mkdir(dirpath)
        if debug:
            print("Creating Dir: {}".format(dirpath))
    
    tracepath = os.path.join(dirpath, "traces")
    if os.path.exists(tracepath) and os.path.isdir(tracepath):
        # shutil.rmtree(tracepath)
        pass
    if not os.path.exists(tracepath):
        os.mkdir(tracepath)
        if debug:
            print("Creating Dir: {}".format(tracepath))

    rawpath = os.path.join(dirpath, "raw")
    if os.path.exists(rawpath) and os.path.isdir(rawpath):
        # shutil.rmtree(rawpath)
        pass
    if not os.path.exists(rawpath):
        os.mkdir(rawpath)
        if debug:
            print("Creating Dir: {}".format(rawpath))

    # create sub dir under raw
    rawpath_current_execution = os.path.join(rawpath, execution_number.zfill(3))
    if os.path.exists(rawpath_current_execution) and os.path.isdir(rawpath_current_execution):
        shutil.rmtree(rawpath_current_execution)
    os.mkdir(rawpath_current_execution)
    if debug:
        print("Creating Dir: {}".format(rawpath_current_execution))

    # move data to raw -- might have to be very specific
    curdir_files = os.listdir(args.wd)
    if debug:
        print("Generated Files in CWD: {}".format(curdir_files))

    for f in curdir_files:
        if "fault-samples" in f:
            TRACE_NAME = f
            break
    else:
        raise Exception("Error: Not Traces in Dir: {}".format(args.wd, curdir_files))

    mv_cmd = "cd {}; mv fault* {}".format(args.wd, rawpath_current_execution)
    subprocess.call(mv_cmd, shell=True)
    if debug:
        print("Moving traces to raw with cmd: {}".format(mv_cmd))
    
    # processing data
    RAW_TRACE_PATH = os.path.join(rawpath_current_execution, TRACE_NAME)
    PROCESSED_TRACE_PATH = os.path.join(tracepath, "{}_000.txt".format(execution_number.zfill(3)))
    merge_cmd = "python3 {} -i {} -o {}".format(MERGE_SCRIPT, RAW_TRACE_PATH, PROCESSED_TRACE_PATH) 
    subprocess.call(merge_cmd, shell=True)
    if debug:
        print("Merging Traces with cmd: {}".format(merge_cmd))

if __name__ == "__main__":
    main()