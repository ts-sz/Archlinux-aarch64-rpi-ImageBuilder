#!/usr/bin/env bash
: <<COMMENTBLOCK
title       :build-archlinux-rpi-aarch64-img.sh
description :
author      :Valeriu Stinca
email       :ts@strategic.zone
date        :20250712
version     :3
notes       : 
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

configure_locale() {
  echo "Setting locale and keymap..."
  # Convert space-delimited locales to newline-separated format
  echo "$OS_LOCALES" | tr ' ' '\n' > $WORKDIR_BASE/root/etc/locale.gen
  arch-chroot $WORKDIR_BASE/root locale-gen
  echo "LANG=${OS_DEFAULT_LOCALE}" > $WORKDIR_BASE/root/etc/locale.conf
  echo -e "KEYMAP=${OS_KEYMAP}\nFONT=eurlatgr" > $WORKDIR_BASE/root/etc/vconsole.conf
}

configure_timezone() {
  echo "Setting timezone..."
  ln -sf /usr/share/zoneinfo/${OS_TIMEZONE} $WORKDIR_BASE/root/etc/localtime
}

install_packages() {
  echo "Initializing pacman keyring..."
  arch-chroot $WORKDIR_BASE/root pacman-key --init
  arch-chroot $WORKDIR_BASE/root pacman-key --populate archlinuxarm

  echo "Updating pacman database and packages..."
  arch-chroot $WORKDIR_BASE/root pacman -Syu --noconfirm archlinux-keyring

  # Remove without confirmation linux-aarch64
  arch-chroot $WORKDIR_BASE/root pacman -R --noconfirm linux-aarch64 uboot-raspberrypi

  # if RPI_MODEL is 5, install linux-rpi-16k and rpi5-eeprom
  if [ "$RPI_MODEL" = "5" ]; then
    echo "Installing linux-rpi-16k and rpi5-eeprom..."
    arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm linux-rpi-16k rpi5-eeprom
  elif [ "$RPI_MODEL" = "4" ]; then
    echo "Installing linux-rpi and rpi4-eeprom..."
    arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm linux-rpi rpi4-eeprom
  fi

  echo "Installing packages..."
  arch-chroot $WORKDIR_BASE/root pacman -S --noconfirm $PACKAGES
}

configure_rpi() {
  echo "Configuring Raspberry Pi boot options..."
  echo -e "\nos_check=0" >> $WORKDIR_BASE/root/boot/config.txt
}

configure_system() {
  echo "Setting hostname..."
  echo "$RPI_HOSTNAME" > $WORKDIR_BASE/root/etc/hostname
  arch-chroot $WORKDIR_BASE/root hostnamectl set-hostname "$RPI_HOSTNAME"

  echo "Setting a new root password..."
  arch-chroot $WORKDIR_BASE/root /bin/bash -c "echo root:$ROOT_PASSWORD | chpasswd"
}

configure_networking() {
  echo "Setting up wired and wireless networking..."
  rm -rf $WORKDIR_BASE/root/etc/systemd/network/*

  cat <<EOF > $WORKDIR_BASE/root/etc/systemd/network/20-wired.network
[Match]
Type=ether

[Network]
DHCP=yes
DNSSEC=no

[Address]
Address=${STATIC_WIRED_IP}

[DHCPv4]
RouteMetric=100

[IPv6AcceptRA]
RouteMetric=100
EOF

  cat <<EOF > $WORKDIR_BASE/root/etc/systemd/network/20-wireless.network
[Match]
Type=wlan

[Network]
DHCP=yes
DNSSEC=no

[DHCPv4]
RouteMetric=600

[IPv6AcceptRA]
RouteMetric=600
EOF

  arch-chroot $WORKDIR_BASE/root systemctl enable systemd-networkd systemd-resolved
  arch-chroot $WORKDIR_BASE/root systemctl enable iwd

  mkdir -p $WORKDIR_BASE/root/var/lib/iwd
  cat <<EOF > $WORKDIR_BASE/root/var/lib/iwd/${WIFI_SSID}.psk
[Security]
PreSharedKey=${WIFI_PASSWORD}

[Settings]
AutoConnect=true
EOF
}

configure_ssh() {
  echo "Setting up SSH..."
  # Set up SSH keys
  mkdir -p $WORKDIR_BASE/root/root/.ssh
  echo "$SSH_PUB_KEY" > $WORKDIR_BASE/root/root/.ssh/authorized_keys
  chmod 700 $WORKDIR_BASE/root/root/.ssh
  chmod 600 $WORKDIR_BASE/root/root/.ssh/authorized_keys

  # Create separate SSH config files
  mkdir -p $WORKDIR_BASE/root/etc/ssh/sshd_config.d/
  echo "UseDNS no" > $WORKDIR_BASE/root/etc/ssh/sshd_config.d/10-dns.conf
  echo "Port 34522" > $WORKDIR_BASE/root/etc/ssh/sshd_config.d/20-port.conf
  echo "PermitRootLogin prohibit-password" > $WORKDIR_BASE/root/etc/ssh/sshd_config.d/30-root-login.conf
  echo "AddressFamily any" > $WORKDIR_BASE/root/etc/ssh/sshd_config.d/40-address-family.conf
}

configure_fstab() {
  echo "Updating fstab..."
  echo "LABEL=PI-BOOT  /boot   vfat    defaults        0       0" > $WORKDIR_BASE/root/etc/fstab
}

final_message() {
  echo "Installation is complete. Insert the SD card into your Raspberry Pi and power it on."
}

### MAIN
ascii_banner
configure_locale
configure_timezone
install_packages
configure_rpi
configure_system
configure_networking
configure_ssh
configure_fstab
final_message