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

# Check if the user is root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# Restart teh service systemd-binfmt.service
echo "Restarting systemd-binfmt.service..."
systemctl restart systemd-binfmt.service

# Check if the disk exists
echo "Checking if the disk $LOOP_DEVICE exists..."
if [ ! -b "$LOOP_DEVICE" ]; then
  echo "The disk $LOOP_DEVICE does not exist. Exiting."
  exit 1
fi

echo "YES! ls -l $LOOP_DEVICE"
exit 0
# Partition the disk using parted
echo "Setting up the disk..."
parted --script ${LOOP_DEVICE} mklabel msdos
parted --script ${LOOP_DEVICE} mkpart primary fat32 1MiB 257MiB
parted --script ${LOOP_DEVICE} set 1 lba on
parted --script ${LOOP_DEVICE} mkpart primary 257MiB 100%

# Create file systems
echo "Creating file systems..."
mkfs.vfat ${LOOP_DEVICE}p1 -F 32 -n PI-BOOT
mkfs.ext4 -q -E lazy_itable_init=0,lazy_journal_init=0 -F ${LOOP_DEVICE}p2 -L PI-ROOT

# Mount partitions
echo "Mounting partitions..."
mkdir -p "${WORKDIR_BASE}/root"
mount ${LOOP_DEVICE}p2 "${WORKDIR_BASE}/root"
mkdir -p "${WORKDIR_BASE}/root/boot"
mount ${LOOP_DEVICE}p1 "${WORKDIR_BASE}/root/boot"


# If the checksum is correct, proceed with extraction
echo "Extracting root filesystem..."
bsdtar -xpf "$WORKDIR_BASE/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz" -C $WORKDIR_BASE/root
sync

# Make the new root folder a mount point
echo "Making the new root folder a mount point..."
mount --bind $WORKDIR_BASE/root $WORKDIR_BASE/root

echo "Setting locale and keymap..."
# Add locales to /etc/locale.gen within the chroot environment
arch-chroot $WORKDIR_BASE/root sed -i -e '/^#en_US.UTF-8 UTF-8/s/^#//' \
       -e '/^#en_US ISO-8859-1/s/^#//' \
       -e '/^#fr_FR.UTF-8 UTF-8/s/^#//' \
       -e '/^#fr_FR ISO-8859-1/s/^#//' \
       -e '/^#fr_FR@euro ISO-8859-15/s/^#//' /etc/locale.gen

# Generate and set the default locale within the chroot environment
arch-chroot $WORKDIR_BASE/root locale-gen
arch-chroot $WORKDIR_BASE/root /bin/bash -c 'echo "LANG=en_US.UTF-8" | tee /etc/locale.conf'

# Set the system locale within the chroot environment
arch-chroot $WORKDIR_BASE/root /bin/bash -c "localectl set-locale LANG=$default_locale"

# Modify keymap in vconsole within the chroot environment
arch-chroot $WORKDIR_BASE/root /bin/bash -c "echo -e "KEYMAP=us-acentos\nFONT=eurlatgr"| tee /etc/vconsole.conf"

# Add keymap to vconsole.conf within the chroot environment
arch-chroot $WORKDIR_BASE/root /bin/bash -c 'echo -e "KEYMAP=us-acentos\nFONT=eurlatgr"| tee /etc/vconsole.conf'

echo "Setting timezone..."
# Set the timezone within the chroot environment
arch-chroot $WORKDIR_BASE/root /bin/bash -c "ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime"

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
arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm base-devel dosfstools git mkinitcpio-utils neovim nftables openssh python qrencode rsync sudo tailscale uboot-tools unzip zerotier-one zsh

echo "Installing linux-${$RPI_MODEL} kernel and eeprom..."
echo "Model: $model"
if [[ $RPI_MODEL == 4 ]]
then
  arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm rpi4-eeprom
elif [[ $RPI_MODEL == 5 ]]
then
  arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm rpi5-eeprom
fi

echo "Setup hostname..."
# Set the hostname
echo "$RPI_HOSTNAME" > $WORKDIR_BASE/root/etc/hostname
arch-chroot $WORKDIR_BASE/root hostnamectl set-hostname "$RPI_HOSTNAME"

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
arch-chroot $WORKDIR_BASE/root /bin/bash -c 'echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMidTQ6KGfZtonNKd1HtNPPDiPtzEmlg5yOduvmZzTA valerius laptop" | tee /root/.ssh/authorized_keys'
arch-chroot $WORKDIR_BASE/root chmod 700 /root/.ssh
arch-chroot $WORKDIR_BASE/root chmod 600 /root/.ssh/authorized_keys

# Change SSH port and disable root password authentication
arch-chroot $WORKDIR_BASE/root sed -i 's/#Port 22/Port 34522/g' /etc/ssh/sshd_config
arch-chroot $WORKDIR_BASE/root sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin without-password/g' /etc/ssh/sshd_config

echo "Update fstab..."
# Update /etc/fstab file
arch-chroot $WORKDIR_BASE/root /bin/bash -c 'echo "LABEL=PI-BOOT  /boot   vfat    defaults        0       0" | tee /etc/fstab'

echo "Sync and unmount..."
# sync and unmount
sync
umount "${WORKDIR_BASE}/root/*"

# show the end message
echo "Installation is complete. Insert the SD card into your Raspberry Pi and power it on."
