This is the script I have used to install Ubuntu on my
Acer Chromebook 13 CB5-311-T6R7 on 2014-12-12. The Chrome OS
version pre-installed on the Chromebook was:

	Version 39.0.2171.94
	Platform 6310.61.0 (Official Build) stable-channel nyan_big
	Firmware Google_Nyan_Big.5771.63.0

I am now running a dual-boot configuration with Chrome OS and Ubuntu.
To boot into ubuntu I run "sudo ubuntu" in a Chrome OS Crosh shell session.

Here is a short write-up of te install procedure. I write this a few days
after the fact, so it is possible that I get some of the details wrong..

This tutorial is based on the modified chrubuntu installer posted by
reddit user arm000: http://www.reddit.com/r/chrubuntu/comments/2hhb31/

This script installs a basic ubuntu system and also the NVidia drivers
the Tegra K1 processor and its Kepler GPU.

The script in this directory is a slightly modified version of the
original script. Compare chrubuntu.sh and chrubuntu.sh.orig for details.


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
	wget http://svn.clifford.at/handicraft/2014/chrbook13/chrubuntu.sh
	sudo bash chrubuntu.sh

This will ask you how much space you would like to reserve for Ubuntu. I chose
16 GB. After changing the partition table the script will reboot the device.
The boot loader will then recreate the chrome os partition used for user
content on the smaller partition, leaving the newly created partition for
ubuntu untouched.


==> Installing Ubuntu

Once again, open a Chrome window, press Ctrl + Alt + T to open a terminal
window. Enter the following commands:

	shell
	cd ~/Downloads
	wget http://svn.clifford.at/handicraft/2014/chrbook13/chrubuntu.sh
	sudo bash chrubuntu.sh

This time the script auto-detects that the target partition already exists and
installs ubuntu.

Next install the launcher:

	wget http://svn.clifford.at/handicraft/2014/chrbook13/ubuntu.sh
	sudo mkdir -p /usr/local/bin
	sudo cp ubuntu.sh /usr/local/bin/ubuntu
	sudo chmod +x /usr/local/bin/ubuntu

Now you can boot into ubuntu by running "sudo ubuntu"

