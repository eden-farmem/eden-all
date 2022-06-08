Our systems run on a custom kernel based on 5.11-rc1 
with a couple of patches to support vDSO system calls
for checking status of pages from userspace.


To install this kernel, you can follow the steps below.
1. Clone kernel 5.11-rc1
    https://kernel.ubuntu.com/~kernel-ppa/mainline/v5.11-rc1/
2. Apply patches from below.
3. Build and boot into it. Helper scripts at `scripts/kernel/*`

### Available Patches
1. For vDSO page status calls that support annotations:
    ```
    git am 1-nadavs-vdso-fixes.patch
    git am 2-vdso-page-status-calls.patch
    ```
2. For debugging fault locations, we need code locations. This 
    patch includes ip register value in the fault message sent 
    to userspace so we can locate the fault source.
    ```
    git am 3-include-ip-info-uffd.patch
    ```


