
function progress () {
  arg=$1
  i=${i:-0}
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

  if [ -f ${TARGET_DIR}/${script} ] ; then
    chmod a+x ${TARGET_DIR}/${script}
    chroot ${TARGET_DIR} /bin/bash -c /${script} >> ${LOGFILE} 2>&1
    rm ${TARGET_DIR}/${script}
  fi
}


function setup_chroot () {

  mount -o bind /proc ${TARGET_DIR}/proc
  mount -o bind /dev ${TARGET_DIR}/dev
  mount -o bind /dev/pts ${TARGET_DIR}/dev/pts
  mount -o bind /sys ${TARGET_DIR}/sys

}


function unset_chroot () {

  if [ "x${PROGRESS_PID}" != "x" ]
  then
    end_progress
  fi

  umount ${TARGET_DIR}/proc
  umount ${TARGET_DIR}/dev/pts
  umount ${TARGET_DIR}/dev
  umount ${TARGET_DIR}/sys

}
function install_dev_tools () {

start_progress "Installing development base packages"

#
# Add some development tools and put the alarm user into the
# wheel group. Furthermore, grant ALL privileges via sudo to users
# that belong to the wheel group
#
cat > ${TARGET_DIR}/install-develbase.sh << EOF
pacman -Syy --needed --noconfirm sudo wget dialog base-devel devtools vim rsync git
useradd alarm
usermod -aG wheel alarm
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
EOF

exec_in_chroot install-develbase.sh

end_progress
}

function install_xbase () {

start_progress "Installing X-server basics"

cat > ${TARGET_DIR}/install-xbase.sh <<EOF

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


function setup_tz() {
start_progress "Timezone"
echo "en_US.UTF-8 UTF-8" >> $TARGET_DIR/etc/locale.gen
cp $CURRENT_DIR/pacs.txt  ${TARGET_DIR}/tmp/
cp /etc/timezone $TARGET_DIR/etc/
cp /etc/resolv.conf $TARGET_DIR/etc/
rm -f $TARGET_DIR/etc/localtime

cat > ${TARGET_DIR}/setup-tz.sh << EOF

ln -s /usr/share/zoneinfo/$(cat /etc/timezone) /etc/localtime
locale-gen
pacman -Syy --needed --noconfirm \$(cat /tmp/pacs.txt | xargs)
EOF
exec_in_chroot setup-tz.sh
end_progress
}

function install_xfce4 () {

start_progress "Installing XFCE4"

# add .xinitrc to /etc/skel that defaults to xfce4 session
cat > ${TARGET_DIR}/etc/skel/.xinitrc << EOF
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

cat > ${TARGET_DIR}/install-xfce4.sh << EOF

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

cat > ${TARGET_DIR}/install-utils.sh <<EOF
pacman -Syy --needed --noconfirm  sshfs screen file-roller grub-bios
EOF

exec_in_chroot install-utils.sh

end_progress

}


function install_sound () {

start_progress "Installing sound (alsa/pulseaudio)"

cat > ${TARGET_DIR}/install-sound.sh <<EOF

pacman -Syy --needed --noconfirm \
        alsa-lib alsa-utils alsa-tools alsa-oss alsa-firmware alsa-plugins \
        pulseaudio pulseaudio-alsa
EOF

exec_in_chroot install-sound.sh

# alsa mixer settings to enable internal speakers
mkdir -p ${TARGET_DIR}/var/lib/alsa
cat > ${TARGET_DIR}/var/lib/alsa/asound.state <<EOF
EOF

end_progress

}

function install_grub () {

echo "Installing grub"

cat > ${TARGET_DIR}/install-grub.sh <<EOF
	genfstab -p / >> /etc/fstab
	/usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg
	/usr/sbin/grub-install \${target_disk}
EOF

exec_in_chroot install-grub.sh

}
