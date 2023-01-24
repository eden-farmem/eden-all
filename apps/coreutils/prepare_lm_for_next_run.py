import argparse
import os
import stat
import subprocess
from defs import ROOT, ROOT_OUTPUT
from common import read_conf_from_init_sh, read_next_execution_number_from_file, compute_memory_usage_with_percent, no_next_execution,read_default_lm_bytes_from_trace_sh


def prepare_env(args):


    if args.percent != 0:
        debug = args.d
        next_execution_number = read_next_execution_number_from_file(args.name)
        if no_next_execution(args.name, next_execution_number) != True:
            if debug:
                print("next_execution_exists")
            
            percent_mem = compute_memory_usage_with_percent(args.name, next_execution_number, args.percent)
            print(percent_mem)
        else:
            if debug:
                print("no_next_execution")
            
            percent_mem = compute_memory_usage_with_percent(args.name, int(next_execution_number) - 1, args.percent)
            print(percent_mem)
    else:
        percent_mem = read_default_lm_bytes_from_trace_sh()
        print(percent_mem)

def main():
    parser = argparse.ArgumentParser(description='Arguments for insert env to init.sh')
    # add args
    parser.add_argument('-d', action="store_true", help='Print Debug')
    parser.add_argument('--percent', default=0, type=int, help='percentage of max m')
    parser.add_argument('--name', required=True, help="current test case name")
    args = parser.parse_args()
    prepare_env(args)
    if args.d:
        print("[prepare_lm_for_next_run/main]: ", args)
    
if __name__ == "__main__":
    main()
