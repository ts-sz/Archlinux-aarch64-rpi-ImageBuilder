for mac 
sudo diskutil unmount /Volumes/RPI64-BOOT
Volume RPI64-BOOT on disk4s1 unmounted
❯ cd /tmp
❯ unzstd /tmp/sz-rpi-aarch64-aarch64-rpi5_v4507703_20250716.img.zst
/tmp/sz-rpi-aarch64-aarch64-rpi5_v4507703_20250716.img.zst: 4294967296 bytes   
❯ sudo dd if=/tmp/sz-rpi-aarch64-aarch64-rpi5_v4507703_20250716.img of=/dev/rdisk4 bs=4m status=progress
 

 how build image with act on vm => not lxc

 how write / birn in microsd
 how do on usb 
 