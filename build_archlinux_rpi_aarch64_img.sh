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

# Display ASCII banner
echo "ICAgICAgIHwgICAgICAgICAgICAgICAgfCAgICAgICAgICAgICAgICBfKSAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAKICBfX3wgIF9ffCAgIF9ffCAgX2AgfCAgX198ICAgXyBcICAg
X2AgfCAgfCAgIF9ffCAgIF8gIC8gICBfIFwgICBfXyBcICAgIF8gXCAKXF9fIFwgIHwgICAgfCAg
ICAoICAgfCAgfCAgICAgX18vICAoICAgfCAgfCAgKCAgICAgICAgLyAgICggICB8ICB8ICAgfCAg
IF9fLyAKX19fXy8gXF9ffCBffCAgIFxfXyxffCBcX198IFxfX198IFxfXywgfCBffCBcX19ffCAg
IF9fX3wgXF9fXy8gIF98ICBffCBcX19ffCAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgIHxfX18vICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAK" | base64 -d

# Source configuration file
source ./build_config.env

#
# 1. Locale and Language Configuration
#
echo "Setting locale and keymap..."
# Enable required locales in locale.gen
sed -i -e '/^#en_US.UTF-8 UTF-8/s/^#//' \
  -e '/^#en_US ISO-8859-1/s/^#//' \
  -e '/^#fr_FR.UTF-8 UTF-8/s/^#//' \
  -e '/^#fr_FR ISO-8859-1/s/^#//' \
  -e '/^#fr_FR@euro ISO-8859-15/s/^#//' $WORKDIR_BASE/root/etc/locale.gen

# Generate locales (requires chroot)
arch-chroot $WORKDIR_BASE/root locale-gen

# Set system locale
echo "LANG=${DEFAULT_LOCALE}" > $WORKDIR_BASE/root/etc/locale.conf

# Configure keyboard layout and font
echo -e "KEYMAP=${KEYMAP}\nFONT=eurlatgr" > $WORKDIR_BASE/root/etc/vconsole.conf

#
# 2. Timezone Configuration
#
echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/${TIMEZONE} $WORKDIR_BASE/root/etc/localtime

#
# 3. Package Management
#
echo "Initializing pacman keyring..."
# Initialize and populate pacman keyring (requires chroot)
arch-chroot $WORKDIR_BASE/root pacman-key --init
arch-chroot $WORKDIR_BASE/root pacman-key --populate archlinuxarm

echo "Updating pacman database and packages..."
# Update system packages (requires chroot)
arch-chroot $WORKDIR_BASE/root pacman -Syu --noconfirm archlinux-keyring

echo "Installing packages..."
# Install specified packages (requires chroot)
arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm $PACKAGES

# Remove default kernel packages
arch-chroot $WORKDIR_BASE/root pacman -R --noconfirm linux-aarch64 uboot-raspberrypi

# Install Raspberry Pi specific kernel
arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm linux-rpi linux-rpi-headers

#
# 4. Raspberry Pi Configuration
#
# Disable OS check in config.txt
echo -e "\nos_check=0" >> $WORKDIR_BASE/root/boot/config.txt

#
# 5. System Configuration
#
echo "Setup hostname..."
# Set system hostname
echo "$RPI_HOSTNAME" > $WORKDIR_BASE/root/etc/hostname
arch-chroot $WORKDIR_BASE/root hostnamectl set-hostname "$RPI_HOSTNAME"

echo "Setting a new root password..."
# Set root password (requires chroot)
arch-chroot $WORKDIR_BASE/root /bin/bash -c "echo root:$ROOT_PASSWORD | chpasswd"

#
# 6. Network Configuration
#
echo "Setup network..."
# Clean existing network configurations
rm -rf $WORKDIR_BASE/root/etc/systemd/network/*

# Configure wired network
echo "[Match]
Type=ether

[Network]
DHCP=yes
DNSSEC=no

[DHCPv4]
RouteMetric=100

[IPv6AcceptRA]
RouteMetric=100" > $WORKDIR_BASE/root/etc/systemd/network/20-wired.network

# Configure wireless network
echo "[Match]
Type=wlan

[Network]
DHCP=yes
DNSSEC=no
[DHCPv4]
RouteMetric=600

[IPv6AcceptRA]
RouteMetric=600" > $WORKDIR_BASE/root/etc/systemd/network/20-wireless.network

# Enable network services (requires chroot)
arch-chroot $WORKDIR_BASE/root systemctl enable systemd-networkd systemd-resolved

#
# 7. SSH Configuration
#
echo "Add ssh key and setup ssh..."
# Setup SSH directory and authorized keys
mkdir -p $WORKDIR_BASE/root/root/.ssh
echo "$SSH_PUB_KEY" > $WORKDIR_BASE/root/root/.ssh/authorized_keys
chmod 700 $WORKDIR_BASE/root/root/.ssh
chmod 600 $WORKDIR_BASE/root/root/.ssh/authorized_keys

# Configure SSH server
echo "Port 34522" > $WORKDIR_BASE/root/etc/ssh/sshd_config.d/sz-config.conf
echo "PermitRootLogin prohibit-password" >> $WORKDIR_BASE/root/etc/ssh/sshd_config.d/sz-config.conf

#
# 8. Storage Configuration
#
echo "Update fstab..."
# Configure boot partition in fstab
echo "LABEL=PI-BOOT  /boot   vfat    defaults        0       0" > $WORKDIR_BASE/root/etc/fstab

#
# 9. Completion
#
echo "Installation is complete. Insert the SD card into your Raspberry Pi and power it on."