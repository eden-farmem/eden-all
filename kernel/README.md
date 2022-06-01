Our systems run on a custom kernel based on 5.11-rc1 
with a couple of patches to support vDSO system calls
for checking status of pages from userspace.

To install this kernel, you can follow the steps below.
1. Clone kernel 5.11-rc1
    https://kernel.ubuntu.com/~kernel-ppa/mainline/v5.11-rc1/
2. Apply patches
    git am 1-nadavs-vdso-fixes.patch
    git am 2-vdso-page-status-calls.patch
3. Build and boot into it. Helper scripts at `scripts/kernel/*`

