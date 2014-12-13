#!/bin/bash

# (c) 2014, Trapier Marshall <trapier@cumulusnetworks.com>
#
# cheek is a utility for bootstrapping a Cumulus Linux vm image
#
# cheek is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# cheek is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with the Cumulus Linux Troubleshooting Toolkit.
# If not, see <http://www.gnu.org/licenses/>.

#######################################################

# initialize sudo
sudo -v

# create raw image
dd if=/dev/zero of=disk.raw bs=1K seek=$((15*1024*1024)) count=1

#Create partitions
# Number  Start    End        Size       File system  Name       Flags
#  1      2048s    6143s      4096s                   GRUB-BOOT  hidden, bios_grub
#  2      6144s    268287s    262144s                 ONIE-BOOT  hidden
#  3      268288s  792575s    524288s                 CLBOOT
#  4      792576s  31277198s  30484623s               CUMULUS    hidden, lvm

sudo parted -s disk.raw mklabel gpt
sudo parted -s disk.raw mkpart  GRUB-BOOT 2048s    6143s    
sudo parted -s disk.raw mkpart  ONIE-BOOT 6144s    268287s  
sudo parted -s disk.raw mkpart  CLBOOT    268288s  792575s  
sudo parted -s disk.raw mkpart  CUMULUS   792576s  31277198s
sudo parted -s disk.raw set 1 bios_grub on
sudo parted -s disk.raw set 1 hidden on
sudo parted -s disk.raw set 2 hidden on
sudo parted -s disk.raw set 4 hidden on
sudo parted -s disk.raw set 4 lvm on

# create create loopback on disk image
loopdev=$( sudo kpartx -av disk.raw | awk '{print $3}'|sed 's:..$::' |head -n1)
loopdev="/dev/mapper/${loopdev}"

# create logical volumes
sudo vgcreate CUMULUS ${loopdev}p4
sudo lvcreate -n PERSIST -L 16M CUMULUS 
sudo lvcreate -n SYSROOT1 -L 3G CUMULUS 
sudo lvcreate -n SYSROOT2 -L 3G CUMULUS 

# format ext4 filesystems
sudo mkfs.ext4 -L ONIE-BOOT ${loopdev}p2
sudo mkfs.ext4 -L CLBOOT ${loopdev}p3
sudo mkfs.ext4 -L PERSIST /dev/mapper/CUMULUS-PERSIST
sudo mkfs.ext4 -L SYSROOT1 /dev/mapper/CUMULUS-SYSROOT1
sudo mkfs.ext4 -L SYSROOT2 /dev/mapper/CUMULUS-SYSROOT2

# mount disk image
mkdir sysroot
sudo mount /dev/mapper/CUMULUS-SYSROOT1 sysroot
sudo mkdir -p sysroot/boot 
sudo mount ${loopdev}p3 sysroot/boot
sudo mkdir -p sysroot/mnt/persist 
sudo mount /dev/mapper/CUMULUS-PERSIST sysroot/mnt/persist

# debootstrap
sudo ln -s /usr/share/debootstrap/scripts/sid /usr/share/debootstrap/scripts/CumulusLinux-2.2
includes="
       lvm2
       openssh-server
       python-ifupdown2,python-ifupdown2-addons,python-argcomplete,python-ipaddr
       sudo
       "
includes=$(echo ${includes} |tr " " "," )
sudo debootstrap --no-check-gpg --include=${includes} CumulusLinux-2.2 sysroot http://repo.cumulusnetworks.com

# chroot
# - create default user
# - (re)install all downloaded packages and install kernel
sudo chroot sysroot /bin/bash -x << EOCHROOT
useradd -m user -G sudo -s /bin/bash
echo "user:secret" | chpasswd

dpkg -i /var/cache/apt/archives/*
sed -i 's:debootstrap.invalid:repo.cumulusnetworks.com:' /etc/apt/sources.list
apt-get update
apt-get install linux-image
EOCHROOT

# configure getty on ttyS0
echo "T0:23:respawn:/sbin/getty -L ttyS0 115200 vt100" | sudo tee -a sysroot/etc/inittab

# configure fstab
sudo tee -a sysroot/etc/fstab << EOFSTAB
LABEL=SYSROOT1       /               ext4    defaults,noatime,errors=remount-ro      0     1
LABEL=CLBOOT       /boot           ext4    defaults,noatime        0       2
LABEL=PERSIST       /mnt/persist    ext4    defaults,noatime        0       2
EOFSTAB

# add eth0 to interfaces
sudo tee -a sysroot/etc/network/interfaces << EOIFACE
auto eth0  
iface eth0 inet dhcp
EOIFACE

# disable vendor-specific grub entries and enable serial console
sudo ln -sf /dev/null sysroot/etc/grub.d/10_cumulus 
sudo sed -i 's:GRUB_CMDLINE_LINUX_DEFAULT=.*:GRUB_CMDLINE_LINUX_DEFAULT="quiet console=ttyS0":' sysroot/etc/default/grub
echo "GRUB_TERMINAL=serial" | sudo tee -a sysroot/etc/default/grub

# copy out kernel and initrd and unmount disk image
mkdir boot
cp sysroot/boot/initrd.img* sysroot/boot/vmlinuz* boot/
sudo umount sysroot/mnt/persist
sudo umount sysroot/boot
sudo fuser -k sysroot
sudo umount sysroot
sudo vgchange -an CUMULUS
sudo kpartx -d disk.raw

# boot image with surrogate kernel to install grub 
#
#   to bind to a bridge named br0, append the following to the kvm
#   command: -net bridge,br=br0 -net nic,model=e1000
#
sudo kvm -m 1G -kernel boot/vmlinuz* -initrd boot/initrd.img* -hda disk.raw -append "root=/dev/mapper/CUMULUS-SYSROOT1 console=ttyS0" -nographic -serial mon:stdio

# Run the following on the vm console to install grub
# 
#    sudo grub-install /dev/sda
#    sudo update-grub
#    sudo mv /boot/grub/grub.cfg.new /boot/grub/grub.cfg
#    sudo halt
# 
# ###############################################

# boot image with grub installed
sudo kvm -m 1G -hda disk.raw -nographic -serial mon:stdio
