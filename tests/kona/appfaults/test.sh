
#
# Test concurrent page faults
#
bash run.sh -fl="-DUSE_APP_FAULTS -DFAULT_OP=3 -DCONCURRENT" \
    -ko="-DNO_ZEROPAGE_OPT" -t=8  -f 