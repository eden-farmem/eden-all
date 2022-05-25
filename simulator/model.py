import os
import sys
import argparse


# DEFAULTS
HIT_LATENCY = 1.4e-6        # From 2 core, 2000 MB xput
PAGEFAULT_LATENCY = 18.5e-6     # FIXME Might be wrong!
UPCALL_LATENCY = 1e-6
KONA_PF_RATE = 110000

# One distribution
def xput_one(h, th, tp, cores):
    return cores * 1.0 / (th + (1 - h) * tp)

def pf_one(h, th, tp, cores):
    return cores * (1 - h) / (th + (1 - h) * tp)

def rev_pf_one(pf, h, th, cores):
    miss = 1.0 - h
    return (cores * miss * 1.0 / pf - th) / miss

def run_one(cores, hitrate, 
        upcalls=False,
        hitcost=HIT_LATENCY,
        pfcost=PAGEFAULT_LATENCY,
        upcost=UPCALL_LATENCY,
        konabw=KONA_PF_RATE):
    if not upcalls:
        faults = pf_one(hitrate, hitcost, pfcost, cores)
        pfcost_adjusted = pfcost if faults < konabw \
            else rev_pf_one(konabw, hitrate, HIT_LATENCY, cores)
        xput = xput_one(hitrate, hitcost, pfcost_adjusted, cores)
        faults = pf_one(hitrate, hitcost, pfcost_adjusted, cores)
    else:
        faults = pf_one(hitrate, hitcost, upcost, cores)
        pfcost_adjusted = upcost if faults < konabw \
            else rev_pf_one(konabw, hitrate, HIT_LATENCY, cores)
        xput = xput_one(hitrate, hitcost, pfcost_adjusted, cores)
        faults = pf_one(hitrate, hitcost, pfcost_adjusted, cores)
    return (int(xput), int(faults))


def main():
    parser = argparse.ArgumentParser("Model")
    parser.add_argument('-c', '--cores', action='store', help='app cores', type=int, required=True)
    parser.add_argument('-h1', '--hitr', action='store', help='hit ratio', type=float, required=True)
    parser.add_argument('-th', '--servicetime', action='store', help='service time (ns)', type=int, required=True)
    parser.add_argument('-tf', '--faulttime', action='store', help='fault time (ns)', type=int, required=True)
    parser.add_argument('-kr', '--konarate', action='store', help='kona page fault bandwidth', type=int, required=True)
    parser.add_argument('-u', '--upcall', action='store_true', help='unblock cores with upcalls', default=False)
    parser.add_argument('-tu', '--upcost', action='store', help='upcall time (ns)', type=int)
    args = parser.parse_args()

    assert not args.upcall or args.upcost, "provide upcall cost with -tu"
    upcost = args.upcost*1e-9 if args.upcall else None
    (xput, pf) = run_one(args.cores, args.hitr,
        upcalls=args.upcall,
        hitcost=args.servicetime*1e-9,
        pfcost=args.faulttime*1e-9,
        upcost=upcost,
        konabw=args.konarate)
    print("{},{},{},{},{},{}".format(args.cores, args.hitr, \
        args.servicetime, args.faulttime, xput, pf))

if __name__ == '__main__':
    main()
