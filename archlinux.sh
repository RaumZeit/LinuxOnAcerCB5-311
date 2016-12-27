set -e

CWD=`pwd`
MY_REPO_PATH="http://www.tbi.univie.ac.at/~ronny/alarm/"
MY_CHROOT_DIR=/tmp/arfs
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
        chromium chromium-pepper-flash \
        xorg-server xorg-server-utils xorg-apps xf86-input-synaptics \
        xorg-twm xorg-xclock xterm xorg-xinit xorg-utils
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

sed -i 's/#IgnorePkg   =/IgnorePkg   = xorg-server xorg-server-common xf86-input-evdev xf86-input-synaptics/' /etc/pacman.conf

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

packages=(linux-nyan-3.10.18-17-armv7h.pkg.tar.xz
          linux-nyan-headers-3.10.18-17-armv7h.pkg.tar.xz)

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

packages=(gpu-nvidia-tegra-k1-nvrm-21.5.0-3-armv7h.pkg.tar.xz
          gpu-nvidia-tegra-k1-x11-21.5.0-3-armv7h.pkg.tar.xz
          gpu-nvidia-tegra-k1-openmax-21.5.0-3-armv7h.pkg.tar.xz
          gpu-nvidia-tegra-k1-openmax-codecs-21.5.0-3-armv7h.pkg.tar.xz
          gpu-nvidia-tegra-k1-libcuda-21.5.0-3-armv7h.pkg.tar.xz)

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
state.HDATegra {
	control.1 {
		iface CARD
		name 'HDMI/DP,pcm=3 Jack'
		value false
		comment {
			access read
			type BOOLEAN
			count 1
		}
	}
	control.2 {
		iface MIXER
		name 'IEC958 Playback Con Mask'
		value '0fff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
		comment {
			access read
			type IEC958
			count 1
		}
	}
	control.3 {
		iface MIXER
		name 'IEC958 Playback Pro Mask'
		value '0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
		comment {
			access read
			type IEC958
			count 1
		}
	}
	control.4 {
		iface MIXER
		name 'IEC958 Playback Default'
		value '0400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
		comment {
			access 'read write'
			type IEC958
			count 1
		}
	}
	control.5 {
		iface MIXER
		name 'IEC958 Playback Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.6 {
		iface PCM
		device 3
		name ELD
		value ''
		comment {
			access 'read volatile'
			type BYTES
			count 0
		}
	}
	control.7 {
		iface PCM
		device 3
		name 'Playback Channel Map'
		value.0 0
		value.1 0
		value.2 0
		value.3 0
		value.4 0
		value.5 0
		value.6 0
		value.7 0
		comment {
			access 'read write'
			type INTEGER
			count 8
			range '0 - 36'
		}
	}
}
state.Venice2 {
	control.1 {
		iface MIXER
		name 'MIC Bias VCM Bandgap'
		value 'High Performance'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 'Low Power'
			item.1 'High Performance'
		}
	}
	control.2 {
		iface MIXER
		name 'DMIC MIC Comp Filter Config'
		value 6
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 15'
		}
	}
	control.3 {
		iface MIXER
		name 'MIC1 Boost Volume'
		value 0
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 2'
			dbmin 0
			dbmax 3000
			dbvalue.0 0
		}
	}
	control.4 {
		iface MIXER
		name 'MIC2 Boost Volume'
		value 0
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 2'
			dbmin 0
			dbmax 3000
			dbvalue.0 0
		}
	}
	control.5 {
		iface MIXER
		name 'MIC1 Volume'
		value 0
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 20'
			dbmin 0
			dbmax 2000
			dbvalue.0 0
		}
	}
	control.6 {
		iface MIXER
		name 'MIC2 Volume'
		value 0
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 20'
			dbmin 0
			dbmax 2000
			dbvalue.0 0
		}
	}
	control.7 {
		iface MIXER
		name 'LINEA Single Ended Volume'
		value 1
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 1'
			dbmin -600
			dbmax 0
			dbvalue.0 0
		}
	}
	control.8 {
		iface MIXER
		name 'LINEB Single Ended Volume'
		value 1
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 1'
			dbmin -600
			dbmax 0
			dbvalue.0 0
		}
	}
	control.9 {
		iface MIXER
		name 'LINEA Volume'
		value 2
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 5'
			dbmin -600
			dbmax 2000
			dbvalue.0 0
		}
	}
	control.10 {
		iface MIXER
		name 'LINEB Volume'
		value 2
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 5'
			dbmin -600
			dbmax 2000
			dbvalue.0 0
		}
	}
	control.11 {
		iface MIXER
		name 'LINEA Ext Resistor Gain Mode'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.12 {
		iface MIXER
		name 'LINEB Ext Resistor Gain Mode'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.13 {
		iface MIXER
		name 'ADCL Boost Volume'
		value 0
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 7'
			dbmin 0
			dbmax 4200
			dbvalue.0 0
		}
	}
	control.14 {
		iface MIXER
		name 'ADCR Boost Volume'
		value 0
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 7'
			dbmin 0
			dbmax 4200
			dbvalue.0 0
		}
	}
	control.15 {
		iface MIXER
		name 'ADCL Volume'
		value 12
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 15'
			dbmin -1200
			dbmax 300
			dbvalue.0 0
		}
	}
	control.16 {
		iface MIXER
		name 'ADCR Volume'
		value 12
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 15'
			dbmin -1200
			dbmax 300
			dbvalue.0 0
		}
	}
	control.17 {
		iface MIXER
		name 'ADC Oversampling Rate'
		value '128*fs'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 '64*fs'
			item.1 '128*fs'
		}
	}
	control.18 {
		iface MIXER
		name 'ADC Quantizer Dither'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.19 {
		iface MIXER
		name 'ADC High Performance Mode'
		value 'High Performance'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 'Low Power'
			item.1 'High Performance'
		}
	}
	control.20 {
		iface MIXER
		name 'DAC Mono Mode'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.21 {
		iface MIXER
		name 'SDIN Mode'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.22 {
		iface MIXER
		name 'SDOUT Mode'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.23 {
		iface MIXER
		name 'SDOUT Hi-Z Mode'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.24 {
		iface MIXER
		name 'Filter Mode'
		value Music
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 Voice
			item.1 Music
		}
	}
	control.25 {
		iface MIXER
		name 'Record Path DC Blocking'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.26 {
		iface MIXER
		name 'Playback Path DC Blocking'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.27 {
		iface MIXER
		name 'Digital BQ Volume'
		value 15
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 15'
			dbmin -1500
			dbmax 0
			dbvalue.0 0
		}
	}
	control.28 {
		iface MIXER
		name 'Digital Sidetone Volume'
		value 0
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 30'
			dbmin 0
			dbmax 3000
			dbvalue.0 0
		}
	}
	control.29 {
		iface MIXER
		name 'Digital Coarse Volume'
		value 0
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 3'
			dbmin 0
			dbmax 1800
			dbvalue.0 0
		}
	}
	control.30 {
		iface MIXER
		name 'Digital Volume'
		value 15
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 15'
			dbmin -1500
			dbmax 0
			dbvalue.0 0
		}
	}
	control.31 {
		iface MIXER
		name 'EQ Coefficients'
		value '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
		comment {
			access 'read write'
			type BYTES
			count 105
		}
	}
	control.32 {
		iface MIXER
		name 'Digital EQ 3 Band Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.33 {
		iface MIXER
		name 'Digital EQ 5 Band Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.34 {
		iface MIXER
		name 'Digital EQ 7 Band Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.35 {
		iface MIXER
		name 'Digital EQ Clipping Detection'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.36 {
		iface MIXER
		name 'Digital EQ Volume'
		value 15
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 15'
			dbmin -1500
			dbmax 0
			dbvalue.0 0
		}
	}
	control.37 {
		iface MIXER
		name 'ALC Enable'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.38 {
		iface MIXER
		name 'ALC Attack Time'
		value '0.5ms'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 '0.5ms'
			item.1 '1ms'
			item.2 '5ms'
			item.3 '10ms'
			item.4 '25ms'
			item.5 '50ms'
			item.6 '100ms'
			item.7 '200ms'
		}
	}
	control.39 {
		iface MIXER
		name 'ALC Release Time'
		value '8s'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 '8s'
			item.1 '4s'
			item.2 '2s'
			item.3 '1s'
			item.4 '0.5s'
			item.5 '0.25s'
			item.6 '0.125s'
			item.7 '0.0625s'
		}
	}
	control.40 {
		iface MIXER
		name 'ALC Make Up Volume'
		value 0
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 12'
			dbmin 0
			dbmax 1200
			dbvalue.0 0
		}
	}
	control.41 {
		iface MIXER
		name 'ALC Compression Ratio'
		value '1:1'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 '1:1'
			item.1 '1:1.5'
			item.2 '1:2'
			item.3 '1:4'
			item.4 '1:INF'
		}
	}
	control.42 {
		iface MIXER
		name 'ALC Expansion Ratio'
		value '1:1'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 '1:1'
			item.1 '2:1'
			item.2 '3:1'
		}
	}
	control.43 {
		iface MIXER
		name 'ALC Compression Threshold Volume'
		value 31
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 31'
			dbmin -3100
			dbmax 0
			dbvalue.0 0
		}
	}
	control.44 {
		iface MIXER
		name 'ALC Expansion Threshold Volume'
		value 31
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 31'
			dbmin -6600
			dbmax -3500
			dbvalue.0 -3500
		}
	}
	control.45 {
		iface MIXER
		name 'DAC HP Playback Performance Mode'
		value 'High Performance'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 'High Performance'
			item.1 'Low Power'
		}
	}
	control.46 {
		iface MIXER
		name 'DAC High Performance Mode'
		value 'High Performance'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 'Low Power'
			item.1 'High Performance'
		}
	}
	control.47 {
		iface MIXER
		name 'Headphone Left Mixer Volume'
		value 3
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 3'
			dbmin -1200
			dbmax 0
			dbvalue.0 0
		}
	}
	control.48 {
		iface MIXER
		name 'Headphone Right Mixer Volume'
		value 3
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 3'
			dbmin -1200
			dbmax 0
			dbvalue.0 0
		}
	}
	control.49 {
		iface MIXER
		name 'Speaker Left Mixer Volume'
		value 3
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 3'
			dbmin -1200
			dbmax 0
			dbvalue.0 0
		}
	}
	control.50 {
		iface MIXER
		name 'Speaker Right Mixer Volume'
		value 3
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 3'
			dbmin -1200
			dbmax 0
			dbvalue.0 0
		}
	}
	control.51 {
		iface MIXER
		name 'Receiver Left Mixer Volume'
		value 3
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 3'
			dbmin -1200
			dbmax 0
			dbvalue.0 0
		}
	}
	control.52 {
		iface MIXER
		name 'Receiver Right Mixer Volume'
		value 3
		comment {
			access 'read write'
			type INTEGER
			count 1
			range '0 - 3'
			dbmin -1200
			dbmax 0
			dbvalue.0 0
		}
	}
	control.53 {
		iface MIXER
		name 'Headphone Volume'
		value.0 26
		value.1 26
		comment {
			access 'read write'
			type INTEGER
			count 2
			range '0 - 31'
			dbmin -6700
			dbmax 300
			dbvalue.0 0
			dbvalue.1 0
		}
	}
	control.54 {
		iface MIXER
		name 'Speaker Volume'
		value.0 20
		value.1 20
		comment {
			access 'read write'
			type INTEGER
			count 2
			range '0 - 39'
			dbmin -4800
			dbmax 1400
			dbvalue.0 0
			dbvalue.1 0
		}
	}
	control.55 {
		iface MIXER
		name 'Receiver Volume'
		value.0 21
		value.1 21
		comment {
			access 'read write'
			type INTEGER
			count 2
			range '0 - 31'
			dbmin -6200
			dbmax 800
			dbvalue.0 0
			dbvalue.1 0
		}
	}
	control.56 {
		iface MIXER
		name 'Headphone Left Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.57 {
		iface MIXER
		name 'Headphone Right Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.58 {
		iface MIXER
		name 'Speaker Left Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.59 {
		iface MIXER
		name 'Speaker Right Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.60 {
		iface MIXER
		name 'Receiver Left Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.61 {
		iface MIXER
		name 'Receiver Right Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.62 {
		iface MIXER
		name 'Zero-Crossing Detection'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.63 {
		iface MIXER
		name 'Enhanced Vol Smoothing'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.64 {
		iface MIXER
		name 'Volume Adjustment Smoothing'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.65 {
		iface MIXER
		name 'Biquad Coefficients'
		value '000000000000000000000000000000'
		comment {
			access 'read write'
			type BYTES
			count 15
		}
	}
	control.66 {
		iface MIXER
		name 'Biquad Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.67 {
		iface MIXER
		name 'HP Right Out Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.68 {
		iface MIXER
		name 'HP Left Out Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.69 {
		iface MIXER
		name 'MIXHPRSEL Mux'
		value 'DAC Only'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 'DAC Only'
			item.1 'HP Mixer'
		}
	}
	control.70 {
		iface MIXER
		name 'MIXHPLSEL Mux'
		value 'DAC Only'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 'DAC Only'
			item.1 'HP Mixer'
		}
	}
	control.71 {
		iface MIXER
		name 'LINMOD Mux'
		value 'Left Only'
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 'Left Only'
			item.1 'Left and Right'
		}
	}
	control.72 {
		iface MIXER
		name 'Right Receiver Mixer Left DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.73 {
		iface MIXER
		name 'Right Receiver Mixer Right DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.74 {
		iface MIXER
		name 'Right Receiver Mixer LINEA Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.75 {
		iface MIXER
		name 'Right Receiver Mixer LINEB Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.76 {
		iface MIXER
		name 'Right Receiver Mixer MIC1 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.77 {
		iface MIXER
		name 'Right Receiver Mixer MIC2 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.78 {
		iface MIXER
		name 'Left Receiver Mixer Left DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.79 {
		iface MIXER
		name 'Left Receiver Mixer Right DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.80 {
		iface MIXER
		name 'Left Receiver Mixer LINEA Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.81 {
		iface MIXER
		name 'Left Receiver Mixer LINEB Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.82 {
		iface MIXER
		name 'Left Receiver Mixer MIC1 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.83 {
		iface MIXER
		name 'Left Receiver Mixer MIC2 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.84 {
		iface MIXER
		name 'Right Speaker Mixer Left DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.85 {
		iface MIXER
		name 'Right Speaker Mixer Right DAC Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.86 {
		iface MIXER
		name 'Right Speaker Mixer LINEA Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.87 {
		iface MIXER
		name 'Right Speaker Mixer LINEB Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.88 {
		iface MIXER
		name 'Right Speaker Mixer MIC1 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.89 {
		iface MIXER
		name 'Right Speaker Mixer MIC2 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.90 {
		iface MIXER
		name 'Left Speaker Mixer Left DAC Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.91 {
		iface MIXER
		name 'Left Speaker Mixer Right DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.92 {
		iface MIXER
		name 'Left Speaker Mixer LINEA Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.93 {
		iface MIXER
		name 'Left Speaker Mixer LINEB Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.94 {
		iface MIXER
		name 'Left Speaker Mixer MIC1 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.95 {
		iface MIXER
		name 'Left Speaker Mixer MIC2 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.96 {
		iface MIXER
		name 'Right Headphone Mixer Left DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.97 {
		iface MIXER
		name 'Right Headphone Mixer Right DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.98 {
		iface MIXER
		name 'Right Headphone Mixer LINEA Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.99 {
		iface MIXER
		name 'Right Headphone Mixer LINEB Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.100 {
		iface MIXER
		name 'Right Headphone Mixer MIC1 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.101 {
		iface MIXER
		name 'Right Headphone Mixer MIC2 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.102 {
		iface MIXER
		name 'Left Headphone Mixer Left DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.103 {
		iface MIXER
		name 'Left Headphone Mixer Right DAC Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.104 {
		iface MIXER
		name 'Left Headphone Mixer LINEA Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.105 {
		iface MIXER
		name 'Left Headphone Mixer LINEB Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.106 {
		iface MIXER
		name 'Left Headphone Mixer MIC1 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.107 {
		iface MIXER
		name 'Left Headphone Mixer MIC2 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.108 {
		iface MIXER
		name 'STENR Mux'
		value Normal
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 Normal
			item.1 'Sidetone Right'
		}
	}
	control.109 {
		iface MIXER
		name 'STENL Mux'
		value Normal
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 Normal
			item.1 'Sidetone Left'
		}
	}
	control.110 {
		iface MIXER
		name 'LTENR Mux'
		value Normal
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 Normal
			item.1 Loopthrough
		}
	}
	control.111 {
		iface MIXER
		name 'LTENL Mux'
		value Normal
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 Normal
			item.1 Loopthrough
		}
	}
	control.112 {
		iface MIXER
		name 'LBENR Mux'
		value Normal
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 Normal
			item.1 Loopback
		}
	}
	control.113 {
		iface MIXER
		name 'LBENL Mux'
		value Normal
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 Normal
			item.1 Loopback
		}
	}
	control.114 {
		iface MIXER
		name 'Right ADC Mixer IN12 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.115 {
		iface MIXER
		name 'Right ADC Mixer IN34 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.116 {
		iface MIXER
		name 'Right ADC Mixer IN56 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.117 {
		iface MIXER
		name 'Right ADC Mixer LINEA Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.118 {
		iface MIXER
		name 'Right ADC Mixer LINEB Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.119 {
		iface MIXER
		name 'Right ADC Mixer MIC1 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.120 {
		iface MIXER
		name 'Right ADC Mixer MIC2 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.121 {
		iface MIXER
		name 'Left ADC Mixer IN12 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.122 {
		iface MIXER
		name 'Left ADC Mixer IN34 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.123 {
		iface MIXER
		name 'Left ADC Mixer IN56 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.124 {
		iface MIXER
		name 'Left ADC Mixer LINEA Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.125 {
		iface MIXER
		name 'Left ADC Mixer LINEB Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.126 {
		iface MIXER
		name 'Left ADC Mixer MIC1 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.127 {
		iface MIXER
		name 'Left ADC Mixer MIC2 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.128 {
		iface MIXER
		name 'LINEB Mixer IN2 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.129 {
		iface MIXER
		name 'LINEB Mixer IN4 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.130 {
		iface MIXER
		name 'LINEB Mixer IN6 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.131 {
		iface MIXER
		name 'LINEB Mixer IN56 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.132 {
		iface MIXER
		name 'LINEA Mixer IN1 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.133 {
		iface MIXER
		name 'LINEA Mixer IN3 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.134 {
		iface MIXER
		name 'LINEA Mixer IN5 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.135 {
		iface MIXER
		name 'LINEA Mixer IN34 Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.136 {
		iface MIXER
		name 'DMIC Mux'
		value ADC
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 ADC
			item.1 DMIC
		}
	}
	control.137 {
		iface MIXER
		name 'MIC2 Mux'
		value IN34
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 IN34
			item.1 IN56
		}
	}
	control.138 {
		iface MIXER
		name 'MIC1 Mux'
		value IN12
		comment {
			access 'read write'
			type ENUMERATED
			count 1
			item.0 IN12
			item.1 IN56
		}
	}
	control.139 {
		iface MIXER
		name 'Speakers Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.140 {
		iface MIXER
		name 'Headphone Jack Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.141 {
		iface MIXER
		name 'Mic Jack Switch'
		value false
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
	control.142 {
		iface MIXER
		name 'Int Mic Switch'
		value true
		comment {
			access 'read write'
			type BOOLEAN
			count 1
		}
	}
}
EOF

end_progress

}

echo "" > $LOGFILE

# fw_type will always be developer for Mario.
# Alex and ZGB need the developer BIOS installed though.
fw_type="`crossystem mainfw_type`"
if [ ! "$fw_type" = "developer" ]
  then
    echo -e "\nYou're Chromebook is not running a developer BIOS!"
    echo -e "You need to run:"
    echo -e ""
    echo -e "sudo chromeos-firmwareupdate --mode=todev"
    echo -e ""
    echo -e "and then re-run this script."
    exit 
fi

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
echo "If you don't trust me (Ronny Lorenz a.k.a. RaumZeit) press CTRL+C to quit"
echo "(see https://github.com/RaumZeit/LinuxOnAcerCB5-311 for further details)"
echo ""
read -p "Press [Enter] to proceed installation of ArchLinuxARM"

if [ "$1" != "" ]; then
  target_disk=$1
  echo "Got ${target_disk} as target drive"
  echo ""
  echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
  echo ""
  read -p "Press [Enter] to install ArchLinuxARM on ${target_disk} or CTRL+C to quit"

  kern_part=1
  root_part=2
  ext_size="`blockdev --getsz ${target_disk}`"
  aroot_size=$((ext_size - 65600 - 33))
  cgpt create ${target_disk} 
  cgpt add -i ${kern_part} -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
  cgpt add -i ${root_part} -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
  sync
  blockdev --rereadpt ${target_disk}
  crossystem dev_boot_usb=1
else
  target_disk="`rootdev -d -s`"
  kern_part=6
  root_part=7
  # Do partitioning (if we haven't already)
  ckern_size="`cgpt show -i ${kern_part} -n -s -q ${target_disk}`"
  croot_size="`cgpt show -i ${root_part} -n -s -q ${target_disk}`"
  state_size="`cgpt show -i 1 -n -s -q ${target_disk}`"

  max_archlinux_size=$(($state_size/1024/1024/2))
  rec_archlinux_size=$(($max_archlinux_size - 1))
  # If KERN-C and ROOT-C are one, we partition, otherwise assume they're what they need to be...
  if [ "$ckern_size" =  "1" -o "$croot_size" = "1" ]
  then
    while :
    do
      read -p "Enter the size in gigabytes you want to reserve for ArchLinux. Acceptable range is 5 to $max_archlinux_size  but $rec_archlinux_size is the recommended maximum: " archlinux_size
      if [ ! $archlinux_size -ne 0 2>/dev/null ]
      then
        echo -e "\n\nNumbers only please...\n\n"
        continue
      fi
      if [ $archlinux_size -lt 5 -o $archlinux_size -gt $max_archlinux_size ]
      then
        echo -e "\n\nThat number is out of range. Enter a number 5 through $max_archlinux_size\n\n"
        continue
      fi
      break
    done
    # We've got our size in GB for ROOT-C so do the math...

    #calculate sector size for rootc
    rootc_size=$(($archlinux_size*1024*1024*2))

    #kernc is always 16mb
    kernc_size=32768

    #new stateful size with rootc and kernc subtracted from original
    stateful_size=$(($state_size - $rootc_size - $kernc_size))

    #start stateful at the same spot it currently starts at
    stateful_start="`cgpt show -i 1 -n -b -q ${target_disk}`"

    #start kernc at stateful start plus stateful size
    kernc_start=$(($stateful_start + $stateful_size))

    #start rootc at kernc start plus kernc size
    rootc_start=$(($kernc_start + $kernc_size))

    #Do the real work

    echo -e "\n\nModifying partition table to make room for ArchLinux." 
    echo -e "Your Chromebook will reboot, wipe your data and then"
    echo -e "you should re-run this script..."
    umount -l /mnt/stateful_partition

    # stateful first
    cgpt add -i 1 -b $stateful_start -s $stateful_size -l STATE ${target_disk}

    # now kernc
    cgpt add -i ${kern_part} -b $kernc_start -s $kernc_size -l KERN-C ${target_disk}

    # finally rootc
    cgpt add -i ${root_part} -b $rootc_start -s $rootc_size -l ROOT-C ${target_disk}

    reboot
    exit
  fi
fi

# hwid lets us know if this is a Mario (Cr-48), Alex (Samsung Series 5), ZGB (Acer), etc
hwid="`crossystem hwid`"

chromebook_arch="`uname -m`"
archlinux_arch="armv7"
archlinux_version="latest"

echo -e "\nChrome device model is: $hwid\n"

echo -e "Installing ArchLinuxARM ${archlinux_version}\n"

echo -e "Kernel Arch is: $chromebook_arch  Installing ArchLinuxARM Arch: ${archlinux_arch}\n"

read -p "Press [Enter] to continue..."

if [ ! -d /mnt/stateful_partition/archlinux ]
then
  mkdir /mnt/stateful_partition/archlinux
fi

cd /mnt/stateful_partition/archlinux

if [[ "${target_disk}" =~ "mmcblk" ]]
then
  target_rootfs="${target_disk}p${root_part}"
  target_kern="${target_disk}p${kern_part}"
else
  target_rootfs="${target_disk}${root_part}"
  target_kern="${target_disk}${kern_part}"
fi

echo "Target Kernel Partition: $target_kern  Target Root FS: ${target_rootfs}"

if mount|grep ${target_rootfs}
then
  echo "Refusing to continue since ${target_rootfs} is formatted and mounted. Try rebooting"
  exit 
fi

mkfs.ext4 ${target_rootfs}

if [ ! -d /tmp/arfs ]
then
  mkdir /tmp/arfs
fi
mount -t ext4 ${target_rootfs} /tmp/arfs

tar_file="http://archlinuxarm.org/os/ArchLinuxARM-${archlinux_arch}-${archlinux_version}.tar.gz"

start_progress "Downloading and extracting ArchLinuxARM rootfs"

wget --quiet -O - $tar_file | tar xzvvp -C /tmp/arfs/ >> ${LOGFILE} 2>&1

end_progress

setup_chroot

copy_chros_files

install_dev_tools

install_xbase

install_xfce4

install_sound

install_kernel

install_gpu_driver

install_misc_utils

tweak_misc_stuff

#Set ArchLinuxARM kernel partition as top priority for next boot (and next boot only)
cgpt add -i ${kern_part} -P 5 -T 1 ${target_disk}

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
