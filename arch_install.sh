#!/bin/bash
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

### SET DISK INFO & HOSTNAME ###
echo "Welcome to aleablu's Arch Linux install script :)"
echo "First we need to select the partitions to use: "

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1

partitions_list=$(lsblk -dplnx size -o name,size,type | grep $device | tac)
boot_part=$(dialog --stdout --menu "Select boot partition" 0 0 0 ${partions_list}) || exit 1
root_part=$(dialog --stdout --menu "Select root partition" 0 0 0 ${partions_list}) || exit 1
swap_part=$(dialog --stdout --menu "Select swap partition" 0 0 0 ${partions_list}) || exit 1

hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
: ${hostname:?"hostname cannot be empty"}

### LOGGING, to avoid bash not scrolling in live-usb ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true

### PARTITIONS MANAGEMENT ###
# format to proper filesystem
mkfs.fat -F32 $boot_part
mkswap $swap_part
mkfs.ext4 $root_part
# mount 'em all
mount $root_part /mnt
mkdir -p /mnt/boot/EFI
mount  $boot_part /mnt/boot/EFI
swapon $swap_part

### INSTALL BASE SYSTEM ###
# enable multilib repo
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
# use reflector to select best mirrors
pacman -Syy reflector
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
reflector --verbose -c Germany -c France -c Italy -l 200 -p http --sort rate --save /etc/pacman.d/mirrorlist
# install base system and basic utils
pacstrap /mnt base base-devel linux linux-firmware nano vim zsh
# generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab
# chroot in newly installed base system
arch-chroot /mnt
# enable multilib repo
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

### LOCALE & HOSTNAME CREATION ###
# set hostname
echo $hostname > /etc/hostname
# generate locale
sed -i "/en_US.UTF-8/,/en_US ISO-8859-1/"'s/^#//' /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
export LANG=en_US.UTF-8
# configure system timezone
ln -s /usr/share/zoneinfo/Europe/Rome /etc/localtime
# set hardware clock to use UTC timing
hwclock --systohc --utc

### ROOT & USER CREATION ###
# set root password
p1=$(dialog --stdout --passwordbox "Set root password" 0 0) || exit 1
: ${p1:?"password cannot be empty"}
p2=$(dialog --stdout --passwordbox "Type again the new root password" 0 0) || exit 1
echo [[ "$p1" == "$p2" ]] || ( echo "Passwords did not match"; exit 1; )
echo "root:$p1" | chpasswd --root
# create nonroot user
user=$(dialog --stdout --inputbox "Enter username for your user" 0 0) || exit 1
: ${user:?"user cannot be empty"}
useradd -mU -s /usr/bin/zsh -G wheel,uucp,video,audio,storage,games,input,power "$user"
p1=$(dialog --stdout --passwordbox "Set $user password" 0 0) || exit 1
: ${p1:?"password cannot be empty"}
p2=$(dialog --stdout --passwordbox "Type again the same password" 0 0) || exit 1
echo [[ "$p1" == "$p2" ]] || ( echo "Passwords did not match"; exit 1; )
echo "$user:$p1" | chpasswd --root
# enable group wheel to sudo ops
sed -i "/%wheel ALL=(ALL) ALL/"'s/^#//' /etc/pacman.conf

### GRUB INSTALL ###
# os-prober and ntfs-3g are needed to detect windows partitions
pacman -Syy grub efibootmgr dosfstools os-prober mtools ntfs-3g
grub-install --target=x86_64-efi  --bootloader-id=grub_uefi --recheck
grub-mkconfig -o /boot/grub/grub.cfg

### NETWORKING ###
pacman -Syy netctl wpa_supplicant dhcpcd dialog ppp  
