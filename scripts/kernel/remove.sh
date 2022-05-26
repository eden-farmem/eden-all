
# Remove custom kernel image & related files 
# from boot partition to make space

# NOTE: This is only necessary for custom-built kernels 
# not installed as dpkg packages. 
# If you can find your kernel version with:
#   `dpkg --list 'linux-image*' | grep ^ii` 
# uninstall the version with dpkg following instructions here:
# https://askubuntu.com/questions/345588/what-is-the-safest-way-to-clean-up-boot-partition

VERSION=
BOOTDIR=/boot/

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

sudo rm /boot/vmlinuz-${VERSION}
sudo rm /boot/System.map-${VERSION}
sudo rm /boot/initrd.img-${VERSION}
sudo update-grub
