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

# Restart teh service systemd-binfmt.service
echo "Restarting systemd-binfmt.service..."
systemctl restart systemd-binfmt.service

rpi_hostname="sz-rpi-aarch64-99"

arm_version="aarch64"
# arm_version="armv7"
archlinuxarm="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-${arm_version}-latest.tar.gz"
archlinuxarm_md5="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-${arm_version}-latest.tar.gz.md5"

LOOP_DEVICE="${1}"

# Check if the disk exists
if [ ! -b "$LOOP_DEVICE" ]; then
  echo "The disk $LOOP_DEVICE does not exist. Exiting."
  exit 1
fi
workdir="/tmp/archlinux-aarch64-rpi-builder_$(date +%Y%m%d%H%M%S)/$arm_version"
mkdir -p $workdir

# Define default locale and keymap settings
default_locale="en_US.UTF-8"
timezone="Europe/Paris"
# Partition the disk using parted
parted --script ${LOOP_DEVICE} mklabel msdos
parted --script ${LOOP_DEVICE} mkpart primary fat32 1MiB 257MiB
parted --script ${LOOP_DEVICE} set 1 lba on
parted --script ${LOOP_DEVICE} mkpart primary 257MiB 100%

# Create file systems
mkfs.vfat ${LOOP_DEVICE}p1 -F 32 -n PI-BOOT
mkfs.ext4 -q -E lazy_itable_init=0,lazy_journal_init=0 -F ${LOOP_DEVICE}p2 -L PI-ROOT

# Mount partitions
mkdir -p "${workdir}/root"
mount ${LOOP_DEVICE}p2 "${workdir}/root"
mkdir -p "${workdir}/root/boot"
mount ${LOOP_DEVICE}p1 "${workdir}/root/boot"

# Download and extract root filesystem
if [ ! -f "$workdir/ArchLinuxARM-rpi-${arm_version}-latest.tar.gz" ] || [ ! -f "$workdir/ArchLinuxARM-rpi-${arm_version}-latest.tar.gz.md5" ]; then
  # Download the image and the MD5 checksum file
  wget --quiet "${archlinuxarm}" -O "$workdir/ArchLinuxARM-rpi-${arm_version}-latest.tar.gz"
  wget --quiet "${archlinuxarm_md5}" -O "$workdir/ArchLinuxARM-rpi-${arm_version}-latest.tar.gz.md5"
fi

# Verify MD5 checksum
cd $workdir
md5sum --check "ArchLinuxARM-rpi-${arm_version}-latest.tar.gz.md5"
if [ $? -ne 0 ]; then
  echo "MD5 checksum does not match. Exiting."
  exit 1
fi

# If the checksum is correct, proceed with extraction
bsdtar -xpf "$workdir/ArchLinuxARM-rpi-${arm_version}-latest.tar.gz" -C $workdir/root
sync

# Make the new root folder a mount point
mount --bind $workdir/root $workdir/root

echo "Setting locale and keymap..."
# Add locales to /etc/locale.gen within the chroot environment
arch-chroot $workdir/root sed -i -e '/^#en_US.UTF-8 UTF-8/s/^#//' \
       -e '/^#en_US ISO-8859-1/s/^#//' \
       -e '/^#fr_FR.UTF-8 UTF-8/s/^#//' \
       -e '/^#fr_FR ISO-8859-1/s/^#//' \
       -e '/^#fr_FR@euro ISO-8859-15/s/^#//' /etc/locale.gen

# Generate and set the default locale within the chroot environment
arch-chroot $workdir/root locale-gen
arch-chroot $workdir/root /bin/bash -c 'echo "LANG=en_US.UTF-8" | tee /etc/locale.conf'

# Set the system locale within the chroot environment
arch-chroot $workdir/root /bin/bash -c "localectl set-locale LANG=$default_locale"

# Modify keymap in vconsole within the chroot environment
arch-chroot $workdir/root /bin/bash -c "echo -e "KEYMAP=us-acentos\nFONT=eurlatgr"| tee /etc/vconsole.conf"

# Add keymap to vconsole.conf within the chroot environment
arch-chroot $workdir/root /bin/bash -c 'echo -e "KEYMAP=us-acentos\nFONT=eurlatgr"| tee /etc/vconsole.conf'

echo "Setting timezone..."
# Set the timezone within the chroot environment
arch-chroot $workdir/root /bin/bash -c "ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime"

echo "Initializing pacman keyring..."
# Initialize pacman keyring
arch-chroot $workdir/root pacman-key --init
arch-chroot $workdir/root pacman-key --populate archlinuxarm

echo "Updating pacman database and packages..."
# Update pacman database and packages
arch-chroot $workdir/root pacman -Syu --noconfirm archlinux-keyring
# arch-chroot $workdir/root pacman-key --refresh-keys

echo "Installing packages..."
# Install packages
arch-chroot $workdir/root pacman -S --noconfirm base-devel dosfstools git mkinitcpio-utils neovim nftables openssh python qrencode rsync sudo tailscale uboot-tools unzip zerotier-one zsh

echo "Setup hostname..."
# Set the hostname
echo "$rpi_hostname" > $workdir/root/etc/hostname
arch-chroot $workdir/root hostnamectl set-hostname "$rpi_hostname"

echo "Setup network..."
# delete all network files in /etc/systemd/network
arch-chroot $workdir/root rm -rf /etc/systemd/network/*

# add a network config for network interface in /etc/systemd/network/20-wired.network
arch-chroot $workdir/root /bin/bash -c 'echo "[Match]
Type=ether

[Network]
DHCP=yes
DNSSEC=no

[DHCPv4]
RouteMetric=100

[IPv6AcceptRA]
RouteMetric=100" | tee /etc/systemd/network/20-wired.network'

# add a network config for network interface in /etc/systemd/network/20-wireless.network
arch-chroot $workdir/root /bin/bash -c 'echo "[Match]
Type=wlan

[Network]
DHCP=yes
DNSSEC=no
[DHCPv4]
RouteMetric=600

[IPv6AcceptRA]
RouteMetric=600" | tee /etc/systemd/network/20-wireless.network'

# enable systemd-networkd and systemd-resolved
arch-chroot $workdir/root systemctl enable systemd-networkd systemd-resolved

echo "Add ssh key and setup ssh..."
# Create SSH folder and add key if it does not exist
arch-chroot $workdir/root mkdir -p /root/.ssh
arch-chroot $workdir/root /bin/bash -c 'echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMidTQ6KGfZtonNKd1HtNPPDiPtzEmlg5yOduvmZzTA valerius laptop" | tee /root/.ssh/authorized_keys'
arch-chroot $workdir/root chmod 700 /root/.ssh
arch-chroot $workdir/root chmod 600 /root/.ssh/authorized_keys

# Change SSH port and disable root password authentication
arch-chroot $workdir/root sed -i 's/#Port 22/Port 34522/g' /etc/ssh/sshd_config
arch-chroot $workdir/root sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin without-password/g' /etc/ssh/sshd_config

echo "Update fstab..."
# Update /etc/fstab file
arch-chroot $workdir/root /bin/bash -c 'echo "LABEL=PI-BOOT  /boot   vfat    defaults        0       0" | tee /etc/fstab'

echo "Sync and unmount..."
# sync and unmount
sync
umount "${workdir}/root/*"

# show the end message
echo "Installation is complete. Insert the SD card into your Raspberry Pi and power it on."
