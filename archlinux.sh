set -e

CWD=`pwd`
MY_REPO_PATH="https://raw.githubusercontent.com/albertlincoln/archstrap/master/"
TARGET_DIR="/mnt"
BOOTSTRAP_SOURCE_DIR="/opt/archbootstrap/root.x86_64"
PROGRESS_PID=
LOGFILE="${CWD}/archlinux-install.log"
spin='-\|/'

function progress () {
  arg=$1
  echo -n "$arg   "
  while true
  do
    i=$(( (i+1) %4 ))
    printf "\r$arg   ${spin:$i:1}"
    sleep .1
  done
}

function start_progress () {
  # Start it in the background
  progress "$1" &
  # Save progress() PID
  PROGRESS_PID=$!
  disown
}

function end_progress () {

# Kill progress
kill ${PROGRESS_PID} >/dev/null  2>&1
echo -n " ...done."
echo
}

#
# Note, this function removes the script after execution
#
function exec_in_chroot () {

  script=$1

  if [ -f ${MY_CHROOT_DIR}/${script} ] ; then
    chmod a+x ${MY_CHROOT_DIR}/${script}
    chroot ${MY_CHROOT_DIR} /bin/bash -c /${script} >> ${LOGFILE} 2>&1
    rm ${MY_CHROOT_DIR}/${script}
  fi
}


function setup_chroot () {

  mount -o bind /proc ${MY_CHROOT_DIR}/proc
  mount -o bind /dev ${MY_CHROOT_DIR}/dev
  mount -o bind /dev/pts ${MY_CHROOT_DIR}/dev/pts
  mount -o bind /sys ${MY_CHROOT_DIR}/sys

}


function unset_chroot () {

  if [ "x${PROGRESS_PID}" != "x" ]
  then
    end_progress
  fi

  umount ${MY_CHROOT_DIR}/proc
  umount ${MY_CHROOT_DIR}/dev
  umount ${MY_CHROOT_DIR}/dev/pts
  umount ${MY_CHROOT_DIR}/sys

}

#trap unset_chroot EXIT


function install_dev_tools () {

start_progress "Installing development base packages"

#
# Add some development tools and put the alarm user into the
# wheel group. Furthermore, grant ALL privileges via sudo to users
# that belong to the wheel group
#
cat > ${MY_CHROOT_DIR}/install-develbase.sh << EOF
pacman -Syy --needed --noconfirm sudo wget dialog base-devel devtools vim rsync git
usermod -aG wheel alarm
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
EOF

exec_in_chroot install-develbase.sh

end_progress
}

function install_xbase () {

start_progress "Installing X-server basics"

cat > ${MY_CHROOT_DIR}/install-xbase.sh <<EOF

pacman -Syy --needed --noconfirm \
        iw networkmanager network-manager-applet \
        lightdm lightdm-gtk-greeter \
        chromium \
        xorg-server xorg-apps xf86-input-synaptics \
        xorg-twm xorg-xclock xterm xorg-xinit \
        xorg-server xorg-server-common \
        xorg-server-xvfb \
        xf86-input-mouse \
        xf86-input-keyboard \
        xf86-input-evdev \
        xf86-input-joystick \
        xf86-input-synaptics \
        xf86-video-fbdev
          
systemctl enable NetworkManager
systemctl enable lightdm
EOF

exec_in_chroot install-xbase.sh

end_progress
}


function install_xfce4 () {

start_progress "Installing XFCE4"

# add .xinitrc to /etc/skel that defaults to xfce4 session
cat > ${MY_CHROOT_DIR}/etc/skel/.xinitrc << EOF
#!/bin/sh
#
# ~/.xinitrc
#
# Executed by startx (run your window manager from here)

if [ -d /etc/X11/xinit/xinitrc.d ]; then
  for f in /etc/X11/xinit/xinitrc.d/*; do
    [ -x \"\$f\" ] && . \"\$f\"
  done
  unset f
fi

# exec gnome-session
# exec startkde
exec startxfce4
# ...or the Window Manager of your choice
EOF

cat > ${MY_CHROOT_DIR}/install-xfce4.sh << EOF

pacman -Syy --needed --noconfirm  xfce4 xfce4-goodies
# copy .xinitrc to already existing home of user 'alarm'
cp /etc/skel/.xinitrc /home/alarm/.xinitrc
cp /etc/skel/.xinitrc /home/alarm/.xprofile
sed -i 's/exec startxfce4/# exec startxfce4/' /home/alarm/.xprofile
chown alarm:users /home/alarm/.xinitrc
chown alarm:users /home/alarm/.xprofile
EOF

exec_in_chroot install-xfce4.sh

end_progress

}

function install_misc_utils () {

start_progress "Installing some more utilities"

cat > ${MY_CHROOT_DIR}/install-utils.sh <<EOF
pacman -Syy --needed --noconfirm  sshfs screen file-roller
EOF

exec_in_chroot install-utils.sh

end_progress

}


function install_sound () {

start_progress "Installing sound (alsa/pulseaudio)"

cat > ${MY_CHROOT_DIR}/install-sound.sh <<EOF

pacman -Syy --needed --noconfirm \
        alsa-lib alsa-utils alsa-tools alsa-oss alsa-firmware alsa-plugins \
        pulseaudio pulseaudio-alsa
EOF

exec_in_chroot install-sound.sh

# alsa mixer settings to enable internal speakers
mkdir -p ${MY_CHROOT_DIR}/var/lib/alsa
cat > ${MY_CHROOT_DIR}/var/lib/alsa/asound.state <<EOF
EOF

end_progress

}

echo "" > $LOGFILE

#setterm -blank 0

echo ""
echo "WARNING! This script will install binary packages from an unofficial source!"
echo ""
echo "If you don't trust the devs, press CTRL+C to quit"
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

if [ "${SKIP_FORMAT}" == "" ]; then
	parted -s ${target_disk} -- mklabel msdos \
	    mkpart primary ext2 2048s -1s
	sleep 1
	mkfs.ext4 -L $MACHINE_NAME -O "^has_journal" -m 0 ${target_rootfs}
fi

#mount -t ext4 ${target_rootfs} $TARGET_DIR

tar_file="https://mirrors.kernel.org/archlinux/iso/latest/archlinux-bootstrap-2017.12.01-x86_64.tar.gz"
#start_progress "Downloading and extracting ArchLinuxARM rootfs"
#wget --quiet -O - $tar_file | tar xzvvp -C $MY_TMP_DIR >> ${LOGFILE} 2>&1
cd $(dirname $BOOTSTRAP_SOURCE_DIR)

wget -c $tar_file

if [ ! -d ${BOOTSTRAP_SOURCE_DIR} ]; then
	echo "extract"
fi

echo "Server = http://mirrors.acm.wpi.edu/archlinux/\$repo/os/\$arch" > ${BOOTSTRAP_SOURCE_DIR}/etc/pacman.d/mirrorlist

${BOOTSTRAP_SOURCE_DIR}/bin/arch-chroot ${BOOTSTRAP_SOURCE_DIR} /bin/bash -c "mount -t ext4 ${target_rootfs} ${TARGET_DIR}"

${BOOTSTRAP_SOURCE_DIR}/bin/arch-chroot ${BOOTSTRAP_SOURCE_DIR} /bin/bash -c "pacman-key --init"
${BOOTSTRAP_SOURCE_DIR}/bin/arch-chroot ${BOOTSTRAP_SOURCE_DIR} /bin/bash -c "pacman-key --populate archlinux"

${BOOTSTRAP_SOURCE_DIR}/bin/arch-chroot ${BOOTSTRAP_SOURCE_DIR} /bin/bash -c "pacstrap ${TARGET_DIR} base base-devel grub-bios" 
${BOOTSTRAP_SOURCE_DIR}/bin/arch-chroot ${BOOTSTRAP_SOURCE_DIR} /bin/bash -c "genfstab -p ${TARGET_DIR}  >> ${TARGET_DIR}/etc/fstab"
${BOOTSTRAP_SOURCE_DIR}/bin/arch-chroot ${BOOTSTRAP_SOURCE_DIR} "grub-mkconfig -o /boot/grub/grub.cfg"
${BOOTSTRAP_SOURCE_DIR}/bin/arch-chroot ${BOOTSTRAP_SOURCE_DIR} "grub-install ${target_disk}"
echo $MACHINE_NAME >> ${BOOTSTRAP_SOURCE_DIR}/${TARGET_DIR}/etc/hostname

umount ${target_rootfs}
# dont need to arch-chroot anymore
mount -t ext4 ${target_rootfs} $TARGET_DIR
echo "en_US.UTF-8 UTF-8" >> $TARGET_DIR/etc/locale.gen
chroot ${TARGET_DIR} locale-gen
cp /etc/timezone $TARGET_DIR/etc/
rm $TARGET_DIR/etc/localtime
chroot ${TARGET_DIR} "ln -s /usr/share/zoneinfo/$(cat /etc/timezone) /etc/localtime"
cp pacs.txt  ${TARGET_DIR}/tmp/
chroot ${TARGET_DIR} "pacman -S $(cat /tmp/pacs.txt | xargs)"

end_progress

setup_chroot

install_dev_tools

install_xbase

install_xfce4

install_sound

install_misc_utils



read -p "Press [Enter] to reboot..."

reboot
