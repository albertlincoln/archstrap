#!/bin/bash


PROGRESS_PID=

init () {
    set -Eeuo pipefail

    trap "{
        unset_chroot
    }" ERR
}

CURRENT_DIR=$(dirname "$0")
TARGET_DIR="/mnt/2"
BOOTSTRAP_SOURCE_DIR="/tmp/archstrap/root.x86_64"
LOGFILE="/tmp/install-archlinux.log.$(date +%Y%m%d%H%M%S)"
bootstrap_version="archlinux-bootstrap-2019.04.01-x86_64.tar.gz"
tar_file="https://mirrors.kernel.org/archlinux/iso/latest/"$bootstrap_version
spin='-\|/'

source ./src/functions.sh

init


echo "" > $LOGFILE

#setterm -blank 0

echo ""
read -p "Press [Enter] to proceed installation of ArchLinux"

if [ "$1" != "" ]; then
  target_disk=$1
  echo "Got ${target_disk} as target drive"
  echo ""
  echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
  echo ""
  read -p "Press [Enter] to install ArchLinux on ${target_disk} or CTRL+C to quit"

  root_part=1
  ext_size="`blockdev --getsz ${target_disk}`"
  aroot_size=$((ext_size - 65600 - 33))
else
  echo "Please set your target"
  exit 1
fi

archlinux_arch="x86_64"
archlinux_version="latest"

echo -e "Installing ArchLinux ${archlinux_version}\n"
read -p "Press [Enter] to continue..."

if [[ "${target_disk}" =~ "mmcblk" ]]
then
  target_rootfs="${target_disk}p${root_part}"
else
  target_rootfs="${target_disk}${root_part}"
fi

echo "Target Root FS: ${target_rootfs}"

if mount|grep ${target_rootfs}
then
  echo "Refusing to continue since ${target_rootfs} is formatted and mounted. Try rebooting"
  exit 
fi

MACHINE_NAME="archlnx-$(xxd -p -l 2 /dev/urandom)"
SKIP_FORMAT="${SKIP_FORMAT:-no}"


if [ "${SKIP_FORMAT}" == "no" ]; then
	parted -s ${target_disk} -- mklabel msdos \
	    mkpart primary ext2 2048s -1s
	sleep 1
	mkfs.ext4 -L $MACHINE_NAME -O "^has_journal" -m 0 ${target_rootfs}
fi



mount -t ext4 ${target_rootfs} $TARGET_DIR
SKIP_EXTRACT="${SKIP_EXTRACT:-no}"
if [ "${SKIP_EXTRACT}" == "no" ]; then

	start_progress "Downloading and extracting ArchLinux rootfs"
	wget -c --quiet $tar_file -O /tmp/$bootstrap_version
	mkdir -p $BOOTSTRAP_SOURCE_DIR
	tar xzvvp -f /tmp/$bootstrap_version -C $(dirname $BOOTSTRAP_SOURCE_DIR) >> ${LOGFILE} 2>&1
	rsync -a $BOOTSTRAP_SOURCE_DIR/ $TARGET_DIR

	echo "Server = http://mirrors.acm.wpi.edu/archlinux/\$repo/os/\$arch" > ${TARGET_DIR}/etc/pacman.d/mirrorlist

	${BOOTSTRAP_SOURCE_DIR}/bin/arch-chroot ${TARGET_DIR} pacman-key --init
	${BOOTSTRAP_SOURCE_DIR}/bin/arch-chroot ${TARGET_DIR} pacman-key --populate archlinux

	echo $MACHINE_NAME > ${TARGET_DIR}/etc/hostname

	echo "Done with phase 1"
	end_progress
fi


setup_chroot

setup_tz

install_dev_tools

install_xbase

install_xfce4

install_sound

install_misc_utils



read -p "Press [Enter] to reboot..."

reboot
