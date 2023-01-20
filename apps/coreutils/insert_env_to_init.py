import argparse


TEST_ENV = """
cpwd="$PWD";
cd ..;
. ./tests/lang-default; tmp__=${TMPDIR-/tmp}; test -d "$tmp__" && test -w "$tmp__" || tmp__=.; . ./tests/envvar-check; TMPDIR=$tmp__; export TMPDIR; export VERSION='9.1.127-d586' LOCALE_FR='none' LOCALE_FR_UTF8='none' abs_top_builddir='/home/e7liu/eden-all/apps/coreutils/coreutils' abs_top_srcdir='/home/e7liu/eden-all/apps/coreutils/coreutils' abs_srcdir='/home/e7liu/eden-all/apps/coreutils/coreutils' built_programs='chroot hostid timeout nice who users pinky uptime stty df stdbuf [ b2sum base64 base32 basenc basename cat chcon chgrp chmod chown cksum comm cp csplit cut date dd dir dircolors dirname du echo env expand expr factor false fmt fold ginstall groups head id join kill link ln logname ls md5sum mkdir mkfifo mknod mktemp mv nl nproc nohup numfmt od paste pathchk pr printenv printf ptx pwd readlink realpath rm rmdir runcon seq sha1sum sha224sum sha256sum sha384sum sha512sum shred shuf sleep sort split stat sum sync tac tail tee test touch tr true truncate tsort tty uname unexpand uniq unlink vdir wc whoami yes ' fail=0 host_os=linux-gnu host_triplet='x86_64-pc-linux-gnu' srcdir='.' top_srcdir='.' CONFIG_HEADER='/home/e7liu/eden-all/apps/coreutils/coreutils/lib/config.h' CU_TEST_NAME=`basename '/home/e7liu/eden-all/apps/coreutils/coreutils'`,`echo $tst|sed 's,^\./,,;s,/,-,g'` CC='gcc' AWK='mawk' EGREP='/usr/bin/grep -E' EXEEXT='' MAKE=make PACKAGE_VERSION=9.1.127-d586 PERL='perl' SHELL='/bin/bash' ; test -d /usr/xpg4/bin && PATH='/usr/xpg4/bin:'"$PATH"; PATH='/home/e7liu/eden-all/apps/coreutils/coreutils/src:'"$PATH" ; 9>&2
cd "$cpwd";
## It's a bit confusing here
## pwd is /home/e7liu/eden-all/apps/coreutils/coreutils/gt-cat-proc.sh.Wi1G
## when running cat-proc
## but the TEST_ENV needs to be setup at ./ (parent of tests)
## Thats why we start from cd ..
"""


def insert(args):
    

    trace_sh_addr = args.trace_sh_addr
    init_sh_addr  = args.init_sh_addr
    debug = args.d

    if debug:
        print(args)

    # First, read what's defined in 
    record_trace_conf = False
    confs = []
    with open(trace_sh_addr) as f:
        lines = f.readlines()
        for l in lines:
            l = l.strip("\r\n")
            if "env start" in l:
                record_trace_conf = True
                continue
            if "env end" in l:
                record_trace_conf = False
                continue
            if record_trace_conf == True:
                confs.append(l)
    if debug:
        print("Confs Detected:\n{}\n".format("\n".join(confs)))

    if len(confs) == 0:
        raise Exception("Conf Not Detected")
    else:
        for i, l in enumerate(confs):
            if "FLTRACE_LOCAL_MEMORY_MB" in l:
                l = l.replace("=1", "={}".format(args.m))
                confs[i] = l
                break
        else:
            raise Exception("Conf Error")
        
    print("Finished Reading Conf\n")

    # Second append confs init_sh
    # Signal: ### Custom Conf ###
    init_sh = []
    skip = False
    with open(init_sh_addr) as f:
        for l in f:
            l = l.strip("\r\n")
            if "Custom Conf" in l:
                skip = True
                continue
            if skip == False:
                init_sh.append(l)

    init_sh.append("### Custom Conf ###")
    custom_conf = confs + [""] + [TEST_ENV] + [""]
    init_sh += custom_conf
    with open(init_sh_addr, "w") as f:
        f.write("\n".join(init_sh))
    
    if debug:
        print("Appending:{}\n{}\n".format("### Custom Conf ###","\n".join(custom_conf)))
    
    print("Finished Editing Init\n")

    


def main():
    parser = argparse.ArgumentParser(description='Arguments for insert env to init.sh')
    # add args
    parser.add_argument('--trace_sh_addr', default="./trace.sh", help="path to trace.sh")
    parser.add_argument('--init_sh_addr', default="./coreutils/tests/init.sh",help='path to init.sh')
    parser.add_argument('-m', default="1", help='Local Mem')
    parser.add_argument('-d', action="store_true", help='Print Debug')
    args = parser.parse_args()
    insert(args)

if __name__ == "__main__":
    main()


