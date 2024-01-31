#!/usr/bin/env bash
: <<COMMENTBLOCK
title       :build_localy.sh
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

# Configuration variables
INSTALL_REQUIREMENTS=false
LOOP_IMAGE="archlinux-aarch64-rpi.img"
LOOP_IMAGE_SIZE="4G"
RPI_MODEL=5
ARM_VERSION=aarch64
DEFAULT_LOCALE="en_US.UTF-8"
TIMEZONE="Europe/Paris"
KEYMAP="us-acentos"
SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMidTQ6KGfZtonNKd1HtNPPDiPtzEmlg5yOduvmZzTA valerius laptop"
PACKAGES="base-devel dosfstools git mkinitcpio-utils neovim nftables openssh python qrencode rsync tailscale uboot-tools unzip zerotier-one zsh"

# Set the working directory
WORKDIR_BASE="/tmp/archlinux-rpi-aarch64/$(date +%Y%m%d%H%M%S)"
LOOP_IMAGE_PATH="$WORKDIR_BASE/$LOOP_IMAGE"
ARCH_AARCH64_IMG_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz"
ARCH_AARCH64_IMG_URL_MD5="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz.md5"

# Update the system and install dependencies
if [ "$INSTALL_REQUIREMENTS" = true ]; then
  pacman -Syu --noconfirm
  pacman -S --noconfirm qemu-user-static-binfmt qemu-user-static dosfstools wget libarchive arch-install-scripts
fi

# Create the work directory and set permissions
mkdir -p "$WORKDIR_BASE"
chown -R $USER:$USER "$WORKDIR_BASE"

# Create the image file
fallocate -l "$LOOP_IMAGE_SIZE" "$LOOP_IMAGE_PATH"

# Download the Archlinux aarch64 image
wget -q "$ARCH_AARCH64_IMG_URL" -O "${WORKDIR_BASE}/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz"
wget -q "$ARCH_AARCH64_IMG_URL_MD5" -O "${WORKDIR_BASE}/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz.md5"
md5sum -c "${WORKDIR_BASE}/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz.md5"

# Set up the loop device
losetup -fP "$LOOP_IMAGE_PATH"
LOOP_DEVICE=$(losetup -j "$LOOP_IMAGE_PATH" | cut -d: -f1)

# Create partitions
parted --script "$LOOP_DEVICE" mklabel msdos
parted --script "$LOOP_DEVICE" mkpart primary fat32 1MiB 257MiB
parted --script "$LOOP_DEVICE" mkpart primary ext4 257MiB 100%
parted --script "$LOOP_DEVICE" set 1 boot on
parted --script "$LOOP_DEVICE" print

# Format the partitions
mkfs.vfat -F32 "${LOOP_DEVICE}p1" -n PI-BOOT
mkfs.ext4 -q -E lazy_itable_init=0,lazy_journal_init=0 -F "${LOOP_DEVICE}p2" -L PI-ROOT

# Mount the partitions
mkdir -p "${WORKDIR_BASE}/root"
mount "${LOOP_DEVICE}p2" "$WORKDIR_BASE/root"
mkdir -p "${WORKDIR_BASE}/root/boot"
mount "${LOOP_DEVICE}p1" "$WORKDIR_BASE/root/boot"

# Extract the Archlinux aarch64 image
bsdtar -xpf "${WORKDIR_BASE}/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz" -C "$WORKDIR_BASE/root"
sync

# Start systemd-binfmt if not already running
systemctl start systemd-binfmt

# Make the new root folder a mount point
mount --bind "$WORKDIR_BASE/root" "$WORKDIR_BASE/root"
mount --bind "$WORKDIR_BASE/root/boot" "$WORKDIR_BASE/root/boot"

# Start building the image
echo "Start building the image..."
./build_archlinux_rpi_aarch64_img.sh \
    "$WORKDIR_BASE" \
    "$DEFAULT_LOCALE" \
    "$KEYMAP" \
    "$TIMEZONE" \
    "$PACKAGES" \
    "$RPI_MODEL" \
    "$RPI_HOSTNAME" \
    "$SSH_PUB_KEY"

# Umount Loop Device
umount -R ${WORKDIR_BASE}/root/boot
umount -R ${WORKDIR_BASE}/root
echo "Unmounted $WORKDIR_BASE"
sync