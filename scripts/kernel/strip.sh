
# Strip symbols from kernel modules to 
# reduce size of the custom kernel and fit in boot partition
# https://unix.stackexchange.com/questions/270390/how-to-reduce-the-size-of-the-initrd-when-compiling-your-kernel

VERSION=
MODDIR=/lib/modules/

usage="
-v, --version \t kernel version\n
-f, --force \t force rebuild kona\n
-h, --help \t this usage information message\n"

# parse cli
for i in "$@"
do
case $i in
    -v=*|--version=*)
    VERSION="${i#*=}"
    ;;

    -f|--force)
    FORCE=1
    ;;
    
    -h | --help)
    echo -e $usage
    exit
    ;;

    *)                      # unknown option
    echo "Unknown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

if [ -z "$VERSION" ]; then
    echo "Required parameter: kernel version"
    echo -e $usage
    exit 1
fi

if [ "$VERSION" == "$(uname -r)" ] && ! [[ $FORCE ]]; then
    echo "you're removing the kernel you're in! Use -f to override"
    exit 1
fi

if [ ! -d "$MODDIR/$VERSION/" ]; then
    echo "cannot find modules for this version. do make modules_install?"
    exit 1
fi

pushd $MODDIR/$VERSION/
sudo find . -name *.ko -exec strip --strip-unneeded {} +
popd