
# Strip symbols from kernel modules to 
# reduce size of the custom kernel and fit in boot partition
# https://unix.stackexchange.com/questions/270390/how-to-reduce-the-size-of-the-initrd-when-compiling-your-kernel

VERSION=$1
MODDIR=/lib/modules/

if [ -z "$VERSION" ]; then
    echo "Takes one parameter: kernel version"
    exit 1
fi

if [ "$VERSION" == "$(uname -r)" ]; then
    echo "you're tinkering with the kernel you're in! you sure?"
    exit 1
fi

if [ ! -d "$MODDIR/$VERSION/" ]; then
    echo "cannot find modules for this version. do make modules_install?"
    exit 1
fi

pushd $MODDIR/$VERSION/
sudo find . -name *.ko -exec strip --strip-unneeded {} +
popd

