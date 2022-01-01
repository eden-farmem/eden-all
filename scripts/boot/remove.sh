
# Remove custom kernel image & related files 
# from boot partition to make space

# NOTE: This is only necessary for custom-built kernels 
# not installed as dpkg packages. 
# If you can find your kernel version with:
#   `dpkg --list 'linux-image*' | grep ^ii` 
# uninstall the version with dpkg following instructions here:
# https://askubuntu.com/questions/345588/what-is-the-safest-way-to-clean-up-boot-partition

VERSION=$1
BOOTDIR=/boot/

if [ -z "$VERSION" ]; then
    echo "Takes one parameter: kernel version"
    exit 1
fi

if [ "$VERSION" == "$(uname -r)" ]; then
    echo "you're removing the kernel you're in! you sure?"
    exit 1
fi

sudo rm /boot/vmlinuz-${VERSION}
sudo rm /boot/System.map-${VERSION}
sudo rm /boot/initrd.img-${VERSION}
sudo update-grub
