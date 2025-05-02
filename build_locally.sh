#!/usr/bin/env bash
: <<COMMENTBLOCK
title       :build_localy.sh
description :
author      :Valeriu Stinca
email       :ts@strategic.zone
date        :20230916
version     :0.2
notes       :Refactor using functions
=========================
COMMENTBLOCK

set -e
source ./build_config.env

ascii_banner() {
    echo "ICAgICAgIHwgICAgICAgICAgICAgICAgfCAgICAgICAgICAgICAgICBfKSAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAKICBfX3wgIF9ffCAgIF9ffCAgX2AgfCAgX198ICAgXyBcICAg
X2AgfCAgfCAgIF9ffCAgIF8gIC8gICBfIFwgICBfXyBcICAgIF8gXCAKXF9fIFwgIHwgICAgfCAg
ICAoICAgfCAgfCAgICAgX18vICAoICAgfCAgfCAgKCAgICAgICAgLyAgICggICB8ICB8ICAgfCAg
IF9fLyAKX19fXy8gXF9ffCBffCAgIFxfXyxffCBcX198IFxfX198IFxfXywgfCBffCBcX19ffCAg
IF9fX3wgXF9fXy8gIF98ICBffCBcX19ffCAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg
ICAgIHxfX18vICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAK" | base64 -d
}

install_requirements() {
    if [ "$INSTALL_REQUIREMENTS" = true ]; then
        pacman -Syu --noconfirm
        pacman -S --noconfirm qemu-user-static-binfmt qemu-user-static dosfstools wget libarchive arch-install-scripts
    fi
}

setup_workdir() {
    echo "Setting up working directory..."
    mkdir -p "$WORKDIR_BASE"
    chown -R $USER:$USER "$WORKDIR_BASE"
    fallocate -l "$LOOP_IMAGE_SIZE" "$LOOP_IMAGE_PATH"
}

download_and_verify() {
    echo "Downloading and verifying Arch Linux image..."
    wget -q "$ARCH_AARCH64_IMG_URL" -O "${WORKDIR_BASE}/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz"
    wget -q "$ARCH_AARCH64_IMG_URL_MD5" -O "${WORKDIR_BASE}/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz.md5"
    current_path=$(pwd)
    cd "$WORKDIR_BASE"
    md5sum -c "ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz.md5"
    cd "$current_path"
}

setup_partitions() {
    echo "Setting up disk partitions..."
    losetup -fP "$LOOP_IMAGE_PATH"
    LOOP_DEVICE=$(losetup -j "$LOOP_IMAGE_PATH" | cut -d: -f1)

    parted --script "$LOOP_DEVICE" mklabel msdos
    parted --script "$LOOP_DEVICE" mkpart primary fat32 1MiB 257MiB
    parted --script "$LOOP_DEVICE" mkpart primary ext4 257MiB 100%
    parted --script "$LOOP_DEVICE" set 1 boot on
    parted --script "$LOOP_DEVICE" print
}

create_and_mount_filesystems() {
    echo "Creating and mounting filesystems..."
    LOOP_DEVICE=$(losetup -j "$LOOP_IMAGE_PATH" | cut -d: -f1)
    mkfs.vfat -F32 "${LOOP_DEVICE}p1" -n PI-BOOT
    mkfs.ext4 -q -E lazy_itable_init=0,lazy_journal_init=0 -F "${LOOP_DEVICE}p2" -L PI-ROOT

    mkdir -p "${WORKDIR_BASE}/root"
    mount "${LOOP_DEVICE}p2" "$WORKDIR_BASE/root"
    mkdir -p "${WORKDIR_BASE}/root/boot"
    mount "${LOOP_DEVICE}p1" "$WORKDIR_BASE/root/boot"
}

install_base_system() {
    echo "Installing base system..."
    bsdtar -xpf "${WORKDIR_BASE}/ArchLinuxARM-rpi-${ARM_VERSION}-latest.tar.gz" -C "$WORKDIR_BASE/root"
    sync

    systemctl start systemd-binfmt
    mount --bind "$WORKDIR_BASE/root" "$WORKDIR_BASE/root"
    mount --bind "$WORKDIR_BASE/root/boot" "$WORKDIR_BASE/root/boot"
}

run_system_configuration() {
    echo "Starting system configuration..."
    ./build_archlinux_rpi_aarch64_img.sh
    echo "System configuration completed."
}

cleanup() {
    echo "Cleaning up..."
    if mountpoint -q ${WORKDIR_BASE}/root/boot; then
        umount -Rl ${WORKDIR_BASE}/root/boot || true
    fi

    if mountpoint -q ${WORKDIR_BASE}/root; then
        umount -Rl ${WORKDIR_BASE}/root || true
    fi
    sync
    LOOP_DEVICE=$(losetup -j "$LOOP_IMAGE_PATH" | cut -d: -f1)
    losetup -d $LOOP_DEVICE
    sha256sum "$LOOP_IMAGE_PATH" > "${LOOP_IMAGE_PATH}.sha256"
    echo "SHA256 checksum saved to: ${LOOP_IMAGE_PATH}.sha256"
    echo "Build completed successfully. Image is available at: $LOOP_IMAGE_PATH"
}

### MAIN
ascii_banner
# Ask if cleanup or build image
read -p "Do you want to cleanup or build image? (cleanup/build) " choice
if [ "$choice" = "cleanup" ]; then
  cleanup
  exit 0
elif [ "$choice" = "build" ]; then
  install_requirements
  setup_workdir
  download_and_verify
  setup_partitions
  create_and_mount_filesystems
  install_base_system
  run_system_configuration
  exit 0
else
  echo "Invalid choice. Please enter 'cleanup' or 'build'."
  exit 1
fi