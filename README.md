# Install ArchLinuxARM (alarm) on an Acer Chromebook 13 CB5-311-T6R7

The archlinux.sh script allows one to install ArchLinuxARM
(http://www.archlinuxarm.org) on an Acer Chromebook 13 featuring
the NVIDIA Tegra K1 SoC. Instead of just a base system, the script
installs an entire xfce4 system, so it is kind of similar to what
a Xubuntu distribution would look like.

The script itself is derived from the work Clifford Wolf's chrubuntu
script, which can be found here:

http://www.clifford.at/blog/index.php?/archives/131-Installing-Ubuntu-on-an-Acer-Chromebook-13-Tegra-K1.html

### Remarks
For now, I am running a dual-boot configuration with ChromeOS and
ArchLinuxARM, where the default boots into ArchLinux. Please follow
the instructions at the end of the installer script to set your own
boot default priorities.

Unfortunately, the ChromeOS kernel that resides in the ChromeOS partitions
doesn't support all features necessary for a properly working ArchLinux System.
It lacks some of the required kernel configs for systemd. However, the
ChromeOS kernel can still be used to boot the ArchLinuxARM system, which
helps a lot for an initial setup. To solve the problem with the missing
kernel configs I prepared a dedicated linux kernel package for this device,
which can be found in core/linux-nyan of the acer_cb_tegrak1 branch of my
alarm PKGBUILDs fork:

https://github.com/RaumZeit/PKGBUILDs/tree/master/core/linux-nyan

Additioanlly, I provide a preliminary PKGBUILD for the proprietary
NVIDIA Tegra K1 GPU drivers in the same repository:

https://github.com/RaumZeit/PKGBUILDs/tree/master/alarm/gpu-nvidia-tegra-k1

Both packages work well, and I have not encountered any device specific
problems yet, except that 'Suspend to RAM' is not working (yet).


### Preparation
This script installs an ArchLinuxARM system, together with an xfce4/xorg
environment, including the proprietary NVidia drivers for the Tegra K1
processor and its Kepler GPU.

=> Reinstall Chrome OS in Developer Mode

This sound complicated but is in fact really easy. Simply press

	esc + refresh (f3) + power

this will reboot. On the boot screen press Ctrl + D, then
Ctrl-D again and then ENTER. This will re-install Chrome OS in
dev mode.

When Chrome OS is in dev mode there is a long delay on each
bootup. Simply press Ctrl-D on the boot screen to skip the
delay.


=> Repartition MMC card

Open a Chrome window, press Ctrl + Alt + T to open a terminal
window. Enter the following commands:

	shell
	cd ~/Downloads
	wget https://raw.githubusercontent.com/RaumZeit/LinuxOnAcerCB5-311/archlinux/archlinux.sh
	sudo bash archlinux.sh

This will ask you how much space you would like to reserve for ArchLinuxARM. I chose
16 GB. After changing the partition table the script will reboot the device.
The boot loader will then recreate the chrome os partition used for user
content on the smaller partition, leaving the newly created partition for
alarm untouched.


==> Installing ArchLinuxARM

Once again, open a Chrome window, press Ctrl + Alt + T to open a terminal
window. Enter the following commands:

	shell
	cd ~/Downloads
	wget https://raw.githubusercontent.com/RaumZeit/LinuxOnAcerCB5-311/archlinux/archlinux.sh
	sudo bash archlinux.sh

This time the script auto-detects that the target partition already exists and
installs alarm.

### Usage
After a successful installation, use the following login:

	Username:  alarm
	Password:  alarm

Root access can either be gained via sudo, or the root user:

	Username:  root
	Password:  root

Remember to change the default passwords of both accounts, alarm AND root!

### Post Scriptum
Please note, that currently the chromium browser package available through the
ArchLinux ARM repositories fails to run on many ARM platforms. This is due to some
GCC 5.2 compilation issues that affects other programs as well. To find a
possible fix for this problem is right now under investigation by the
ArchLinux ARM developers.
As long as there is no fixed package available, please refer to the following
forum topic for a working chromium browser package (compiled with GCC 5.1):

http://archlinuxarm.org/forum/viewtopic.php?f=60&t=9109&start=10#p48213

Copyright (c) 2015, 2015 Ronny Lorenz <ronny@tbi.univie.ac.at>
