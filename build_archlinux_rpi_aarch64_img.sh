#!/usr/bin/env bash
: <<COMMENTBLOCK
title       :build-archlinux-rpi-aarch64-img.sh
description :
author      :Valeriu Stinca
email       :ts@strategic.zone
date        :20230916
version     :0.1
notes       :
=========================
COMMENTBLOCK

# Banner
echo "ICAgICAgIHwgICAgICAgICAgICAgICAgfCAgICAgICAgICAgICAgICBfKSAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAKICBfX3wgIF9ffCAgIF9ffCAgX2AgfCAgX198ICAgXyBcICAg
X2AgfCAgfCAgIF9ffCAgIF8gIC8gICBfIFwgICBfXyBcICAgIF8gXCAKXF9fIFwgIHwgICAgfCAg
ICAoICAgfCAgfCAgICAgX18vICAoICAgfCAgfCAgKCAgICAgICAgLyAgICggICB8ICB8ICAgfCAg
IF9fLyAKX19fXy8gXF9ffCBffCAgIFxfXyxffCBcX198IFxfX198IFxfXywgfCBffCBcX19ffCAg
IF9fX3wgXF9fXy8gIF98ICBffCBcX19ffCAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgIHxfX18vICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAK" | base64 -d

# variables
INSTALL_RPI_KERNEL=true
ROOT_PASSWORD="toortoor!"

WORKDIR_BASE="$1"
DEFAULT_LOCALE="$2"
KEYMAP="$3"
TIMEZONE="$4"
PACKAGES="$5"
RPI_MODEL="$6"
RPI_HOSTNAME="$7"
SSH_PUB_KEY="$8"

echo "Setting locale and keymap..."
# Add locales to /etc/locale.gen within the chroot environment
arch-chroot $WORKDIR_BASE/root sed -i -e '/^#en_US.UTF-8 UTF-8/s/^#//' \
  -e '/^#en_US ISO-8859-1/s/^#//' \
  -e '/^#fr_FR.UTF-8 UTF-8/s/^#//' \
  -e '/^#fr_FR ISO-8859-1/s/^#//' \
  -e '/^#fr_FR@euro ISO-8859-15/s/^#//' /etc/locale.gen

# Generate and set the default locale within the chroot environment
arch-chroot $WORKDIR_BASE/root locale-gen
arch-chroot $WORKDIR_BASE/root /bin/bash -c "echo \"LANG=${DEFAULT_LOCALE}\" | tee /etc/locale.conf"

# Set the system locale within the chroot environment
arch-chroot $WORKDIR_BASE/root /bin/bash -c "echo \"LANG=${DEFAULT_LOCALE}\" | tee /etc/locale.conf"

# Add keymap to vconsole.conf within the chroot environment
arch-chroot $WORKDIR_BASE/root /bin/bash -c "echo -e \"KEYMAP=${KEYMAP}\nFONT=eurlatgr\"| tee /etc/vconsole.conf"

echo "Setting timezone..."
# Set the timezone within the chroot environment
arch-chroot $WORKDIR_BASE/root /bin/bash -c "ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"

echo "Initializing pacman keyring..."
# Initialize pacman keyring
arch-chroot $WORKDIR_BASE/root pacman-key --init
arch-chroot $WORKDIR_BASE/root pacman-key --populate archlinuxarm

echo "Updating pacman database and packages..."
# Update pacman database and packages
arch-chroot $WORKDIR_BASE/root pacman -Syu --noconfirm archlinux-keyring
# arch-chroot $WORKDIR_BASE/root pacman-key --refresh-keys

echo "Installing packages..."
# Install packages
arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm $PACKAGES

# Install linux-rpiX kernel and eeprom if variable INSTALL_RPI_KERNEL is true
if [ "$INSTALL_RPI_KERNEL" = true ] ; then
  echo "Installing linux-${$RPI_MODEL} kernel and eeprom..."
  arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm rpi${RPI_MODEL}-eeprom
fi

# Remove linux-aarch64 uboot-raspberrypi
arch-chroot $WORKDIR_BASE/root pacman -R --noconfirm linux-aarch64 uboot-raspberrypi

# install linux-rpi kernel and linux-rpi-headers
arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm linux-rpi linux-rpi-headers

# if RPI_MODEL is 5 add a new line in /boot/config.txt to disable os_check=0
echo "Add os_check=0 in /boot/config.txt for Raspberry Pi 5 to disable os check..."
if [ "$RPI_MODEL" = 5 ] ; then
  echo "Disable os_check=0 in /boot/config.txt..."
  arch-chroot $WORKDIR_BASE/root /bin/bash -c 'echo -e "\nos_check=0" | tee -a /boot/config.txt'
fi

echo "Setup hostname..."
# Set the hostname
arch-chroot $WORKDIR_BASE/root /bin/bash -c "echo \"$RPI_HOSTNAME\" | tee /etc/hostname"
arch-chroot $WORKDIR_BASE/root hostnamectl set-hostname "$RPI_HOSTNAME"

echo "Setting a new root password..."
# Change the root password
arch-chroot $WORKDIR_BASE/root /bin/bash -c "echo root:$ROOT_PASSWORD | chpasswd"

echo "Setup network..."
# delete all network files in /etc/systemd/network
arch-chroot $WORKDIR_BASE/root rm -rf /etc/systemd/network/*

# add a network config for network interface in /etc/systemd/network/20-wired.network
arch-chroot $WORKDIR_BASE/root /bin/bash -c 'echo "[Match]
Type=ether

[Network]
DHCP=yes
DNSSEC=no

[DHCPv4]
RouteMetric=100

[IPv6AcceptRA]
RouteMetric=100" | tee /etc/systemd/network/20-wired.network'

# add a network config for network interface in /etc/systemd/network/20-wireless.network
arch-chroot $WORKDIR_BASE/root /bin/bash -c 'echo "[Match]
Type=wlan

[Network]
DHCP=yes
DNSSEC=no
[DHCPv4]
RouteMetric=600

[IPv6AcceptRA]
RouteMetric=600" | tee /etc/systemd/network/20-wireless.network'

# enable systemd-networkd and systemd-resolved
arch-chroot $WORKDIR_BASE/root systemctl enable systemd-networkd systemd-resolved

echo "Add ssh key and setup ssh..."
# Create SSH folder and add key if it does not exist
arch-chroot $WORKDIR_BASE/root mkdir -p /root/.ssh
arch-chroot $WORKDIR_BASE/root /bin/bash -c "echo \"$SSH_PUB_KEY\" | tee /root/.ssh/authorized_keys"
arch-chroot $WORKDIR_BASE/root chmod 700 /root/.ssh
arch-chroot $WORKDIR_BASE/root chmod 600 /root/.ssh/authorized_keys

# Change SSH port and disable root password authentication
arch-chroot $WORKDIR_BASE/root sed -i 's/#Port 22/Port 34522/g' /etc/ssh/sshd_config
arch-chroot $WORKDIR_BASE/root sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin without-password/g' /etc/ssh/sshd_config

echo "Update fstab..."
# Update /etc/fstab file
arch-chroot $WORKDIR_BASE/root /bin/bash -c 'echo "LABEL=PI-BOOT  /boot   vfat    defaults        0       0" | tee /etc/fstab'

# show the end message
echo "Installation is complete. Insert the SD card into your Raspberry Pi and power it on."
