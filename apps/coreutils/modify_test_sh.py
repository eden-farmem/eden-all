import argparse
import os
import stat
import subprocess

def findall(p, s):
    '''Yields all the positions of
    the pattern p in the string s.'''
    i = s.find(p)
    while i != -1:
        yield i
        i = s.find(p, i+1)

def has_init_sh(lines):
    for l in lines:
        if "tests/init.sh" in l:
            return True
    return False

def runs_the_command(lines, cmd):
    for l in lines:
        if "{} ".format(cmd) in l:
            return True
    return False

def has_env_cmd(lines, cmd):
    for l in lines:
        if "env {}".format(cmd) in l:
            return True
    return False

def has_proc_cmd(lines, cmd):
    for l in lines:
        if "procs" in l and cmd in l:
            return True
    return False

def is_dummy_cases(line, cmd):
    if line.startswith("#"):
        return True
    if line.startswith("print_ver_"):
        return True

    # Not in perl for sort-benchmark-random
    if "print sort(@list)" in line:
        return True    

    return False


def parse_command_from_path(p):
    sh_name = os.path.basename(p)
    cmd = sh_name.split("-")[0]
    return cmd

def parse_type_1(lines, args):
    


    debug = args.d

    cmd = parse_command_from_path(args.path)
    print("[modift_test_sh/parse_type_1]: Auto parsing cmd from path: {}".format(cmd))

    if args.cmd != None:
        if cmd != args.cmd:
            raise Exception("cmd ({}) != args.cmd {}".format(cmd, args.cmd))

        cmd = args.cmd
        if debug:
            print("[modift_test_sh/parse_type_1]: Overwritting cmd ({}) with args.cmd : {}".format(cmd, args.cmd))
    
        

    test_suite_name = os.path.basename(args.path).replace(".sh", "").replace(".pl", "")

    # Type 1: cat-proc
    # require: 
    # (1) include init.sh
    # (2) actually runs `cmd`
    # (3) no env cmd
    # (4) no "procs cmd" defined e.g., procs=$(cmd $mode)
    if not has_init_sh(lines) or not runs_the_command(lines, cmd)\
     or has_env_cmd(lines, cmd)\
     or has_proc_cmd(lines, cmd):
        return False

    if debug:
        print("[modift_test_sh/parse_type_1]: Handling Type 1")
    # Find find all instances of the command
    new_lines = []

    execution_number = 0
    for i, l in enumerate(lines):
        if cmd in l:
            # not dummy
            if is_dummy_cases(l, cmd):
                new_lines.append(l)
                continue

            cmd_instances = list(findall(cmd,l))
            
            dash_cmd_instances = list(findall("--"+cmd,l))

            # Undefined cases
            if len(cmd_instances) >= 2 and len(cmd_instances) - len(dash_cmd_instances) > 1:
                raise Exception("I Don't Know What To Do! {}".format(l))

            cmd_pos = cmd_instances[0]
            if cmd_pos != 0:
                new_command = l[:cmd_pos] + " " + "env $env" + " " + l[cmd_pos:]
            else:
                new_command = "env $env" + " " + l[cmd_pos:]

            new_lines.append(new_command)
            pwd = os.getcwd()
            #new_lines.append('python3 /home/e7liu/eden-all/apps/coreutils/in_folder_result_processing.py --wd="$PWD" -r={} -d --name="{}"'\
            #.format(execution_number, test_suite_name))
            new_lines.append('python3 /home/e7liu/eden-all/apps/coreutils/in_folder_result_processing.py --wd="$PWD" -d --name="{}"'\
            .format(test_suite_name))

            execution_number += 1

            if debug:
                print('[modift_test_sh/parse_type_1]: Found Raw Command:{}'.format(l))


        
        # doesn't matter cmd not in l
        else:
            new_lines.append(l)
            continue

    # Write to new file
    fname = args.path
    new_name = fname.replace(".sh","-modified.sh")
    with open(new_name, "w") as f:
        for l in new_lines:
            f.write(l + "\n")
    subprocess.call(['chmod', '0777', '{}'.format(new_name)])
            
    return True



def modify(args):
    debug = args.d

    if debug:
        print("[modift_test_sh/modify] ", args)

    with open(args.path) as f:
        lines = f.readlines()
        lines = [l.strip('\r\n') for l in lines]
        if parse_type_1(lines, args):
            return True


    
    raise Exception("I Don't Know What To Do!")




def main():
    parser = argparse.ArgumentParser(description='Arguments for insert env to init.sh')
    # add args
    parser.add_argument('--path', required=True, help="path to test_name.sh")
    parser.add_argument('--cmd', default=None, help="current command")
    parser.add_argument('-d', action="store_true", help='Print Debug')
    args = parser.parse_args()
    modify(args)

if __name__ == "__main__":
    main()