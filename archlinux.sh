set -e

CWD=`pwd`
MY_REPO_PATH="https://raw.githubusercontent.com/albertlincoln/archstrap/master/"
MY_CHROOT_DIR=/tmp/fs2clobber
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

trap unset_chroot EXIT

function copy_chros_files () {

  start_progress "Copying files from ChromeOS to ArchLinuxARM rootdir"

  mkdir -p ${MY_CHROOT_DIR}/run/resolvconf
  cp /etc/resolv.conf ${MY_CHROOT_DIR}/run/resolvconf/
  ln -s -f /run/resolvconf/resolv.conf ${MY_CHROOT_DIR}/etc/resolv.conf
  echo alarm > ${MY_CHROOT_DIR}/etc/hostname
  echo -e "\n127.0.1.1\tlocalhost.localdomain\tlocalhost\talarm" >> ${MY_CHROOT_DIR}/etc/hosts

  KERN_VER=`uname -r`
  mkdir -p ${MY_CHROOT_DIR}/lib/modules/$KERN_VER/
  cp -ar /lib/modules/$KERN_VER/* ${MY_CHROOT_DIR}/lib/modules/$KERN_VER/
  mkdir -p ${MY_CHROOT_DIR}/lib/firmware/
  cp -ar /lib/firmware/* ${MY_CHROOT_DIR}/lib/firmware/

  # remove tegra_lp0_resume firmware since it is owned by latest
  # linux-nyan kernel package
  rm ${MY_CHROOT_DIR}/lib/firmware/tegra12x/tegra_lp0_resume.fw

  end_progress
}

function install_dev_tools () {

start_progress "Installing development base packages"

#
# Add some development tools and put the alarm user into the
# wheel group. Furthermore, grant ALL privileges via sudo to users
# that belong to the wheel group
#
cat > ${MY_CHROOT_DIR}/install-develbase.sh << EOF
pacman -Syy --needed --noconfirm sudo wget dialog base-devel devtools vim rsync git vboot-utils
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
        xorg-twm xorg-xclock xterm xorg-xinit
systemctl enable NetworkManager
systemctl enable lightdm
EOF

exec_in_chroot install-xbase.sh

end_progress

#
# ArchLinuxARM repo contains xorg-server >= 1.18 which
# is incompatible with the proprietary NVIDIA drivers
# Thus, we downgrade to xorg-server 1.17 and required
# input device drivers from source package
#
# We also put the xorg-server and xf86-input-evdev/xf86-input-synaptics into
# pacman's IgnorePkg
#
start_progress "Downgrading xorg-server for compatibility with NVIDIA drivers"

cat > ${MY_CHROOT_DIR}/install-xorg-ABI-19.sh << EOF

packages=(xorg-server-1.17.4-2-armv7h.pkg.tar.xz
          xorg-server-common-1.17.4-2-armv7h.pkg.tar.xz
          xorg-server-xvfb-1.17.4-2-armv7h.pkg.tar.xz
          xf86-input-mouse-1.9.1-1-armv7h.pkg.tar.xz
          xf86-input-keyboard-1.8.1-1-armv7h.pkg.tar.xz
          xf86-input-evdev-2.10.0-1-armv7h.pkg.tar.xz
          xf86-input-joystick-1.6.2-5-armv7h.pkg.tar.xz
          xf86-input-synaptics-1.8.3-1-armv7h.pkg.tar.xz
          xf86-video-fbdev-0.4.4-4-armv7h.pkg.tar.xz)

cd /tmp

for p in \${packages[@]}
do
  sudo -u nobody -H wget ${MY_REPO_PATH}/\$p
done

yes | pacman --needed -U  \${packages[@]}

sed -i 's/#IgnorePkg   =/IgnorePkg   = xorg-server xorg-server-common xorg-server-xvfb xf86-input-mouse xf86-input-keyboard xf86-input-evdev xf86-input-joystick xf86-input-synaptics xf86-video-fbdev/' /etc/pacman.conf

EOF

exec_in_chroot install-xorg-ABI-19.sh

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


function install_kernel () {

start_progress "Installing kernel"

cat > ${MY_CHROOT_DIR}/install-kernel.sh << EOF

packages=(linux-nyan-3.10.18-24-armv7h.pkg.tar.xz
          linux-nyan-headers-3.10.18-24-armv7h.pkg.tar.xz)

cd /tmp

for p in \${packages[@]}
do
  sudo -u nobody -H wget ${MY_REPO_PATH}/\$p
done

yes | pacman --needed -U  \${packages[@]}

EOF

exec_in_chroot install-kernel.sh

end_progress

}


function install_gpu_driver () {

start_progress "Installing proprietary NVIDIA drivers"

#
# Install (latest) proprietary NVIDIA Tegra124 drivers
#

cat > ${MY_CHROOT_DIR}/install-tegra.sh << EOF

packages=(gpu-nvidia-tegra-k1-nvrm-21.6.0-1-armv7h.pkg.tar.xz
          gpu-nvidia-tegra-k1-x11-21.6.0-1-armv7h.pkg.tar.xz
          gpu-nvidia-tegra-k1-openmax-21.6.0-1-armv7h.pkg.tar.xz
          gpu-nvidia-tegra-k1-openmax-codecs-21.6.0-1-armv7h.pkg.tar.xz
          gpu-nvidia-tegra-k1-libcuda-21.6.0-1-armv7h.pkg.tar.xz)

cd /tmp

for p in \${packages[@]}
do
  sudo -u nobody -H wget ${MY_REPO_PATH}/\$p
done

yes | pacman --needed -U  --force \${packages[@]}

usermod -aG video alarm
EOF

exec_in_chroot install-tegra.sh

end_progress

}


function tweak_misc_stuff () {

# hack for removing uap0 device on startup (avoid freeze)
echo 'install mwifiex_sdio /sbin/modprobe --ignore-install mwifiex_sdio && sleep 1 && iw dev uap0 del' > ${MY_CHROOT_DIR}/etc/modprobe.d/mwifiex.conf 

cat > ${MY_CHROOT_DIR}/etc/udev/rules.d/99-tegra-lid-switch.rules <<EOF
ACTION=="remove", GOTO="tegra_lid_switch_end"

SUBSYSTEM=="input", KERNEL=="event*", SUBSYSTEMS=="platform", KERNELS=="gpio-keys.4", TAG+="power-switch"

LABEL="tegra_lid_switch_end"
EOF

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

powerd_status="`initctl status powerd`"
if [ ! "$powerd_status" = "powerd stop/waiting" ]
then
  echo -e "Stopping powerd to keep display from timing out..."
  initctl stop powerd
fi

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

parted -s ${target_disk} -- mklabel msdos \
    mkpart primary ext2 64s 4MiB -1s
    
mkfs.ext4 -O "^has_journal" -m 0 ${root_part} 


if [ ! -d /tmp/arfs ]
then
  mkdir /tmp/arfs
fi
mount -t ext4 ${target_rootfs} /tmp/arfs

tar_file="https://mirrors.kernel.org/archlinux/iso/latest/archlinux-bootstrap-2017.12.01-x86_64.tar.gz"

start_progress "Downloading and extracting ArchLinuxARM rootfs"

wget --quiet -O - $tar_file | tar xzvvp -C /tmp/arfs/ >> ${LOGFILE} 2>&1

end_progress

setup_chroot

copy_chros_files

install_dev_tools

install_xbase

install_xfce4

#install_sound

#install_kernel

#install_gpu_driver

install_misc_utils

#tweak_misc_stuff

#Set ArchLinuxARM kernel partition as top priority for next boot (and next boot only)
#cgpt add -i ${kern_part} -P 5 -T 1 ${target_disk}

echo -e "

Installation seems to be complete. If ArchLinux fails when you reboot,
power off your Chrome OS device and then turn it back on. You'll be back
in Chrome OS. If you're happy with ArchLinuxARM when you reboot be sure to run:

sudo cgpt add -i ${kern_part} -P 5 -S 1 ${target_disk}

To make it the default boot option. The ArchLinuxARM login is:

Username:  alarm
Password:  alarm

Root access can either be gained via sudo, or the root user:

Username:  root
Password:  root

We're now ready to start ArchLinuxARM!
"

read -p "Press [Enter] to reboot..."

reboot
