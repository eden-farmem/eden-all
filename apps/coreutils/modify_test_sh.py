import argparse


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

    return False

def parse_type_1(lines, args):
    cmd = args.cmd
    debug = args.d

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

    print("Handling Type 1")
    # Find find all instances of the command
    new_lines = []


    for i, l in enumerate(lines):
        if cmd in l:
            # not dummy
            if is_dummy_cases(l, cmd):
                new_lines.append(l)
                continue

            cmd_instances = list(findall(cmd,l))
            
            # Undefined cases
            if len(cmd_instances) >= 2:
                raise Exception("I Don't Know What To Do! {}".format(l))

            cmd_pos = cmd_instances[0]
            if cmd_pos != 0:
                new_command = l[:cmd_pos] + " " + "env $env" + " " + l[cmd_pos:]
            else:
                new_command = "env $env" + " " + l[cmd_pos:]

            new_lines.append(new_command)
            new_lines.append("python3 in_folder_result_processing.py")

            if debug:
                print('Found Raw Command:\n{}'.format(l))


        
        # doesn't matter cmd not in l
        else:
            new_lines.append(l)
            continue

    for l in new_lines:
        print(l)

    return True



def modify(args):
    debug = args.d

    if debug:
        print(args)

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
    parser.add_argument('--cmd', required=True, help="current command")
    parser.add_argument('-d', action="store_true", help='Print Debug')
    args = parser.parse_args()
    modify(args)

if __name__ == "__main__":
    main()