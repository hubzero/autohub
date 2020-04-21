yum -y install bzip2 net-tools
yum -y install gcc make perl
rpm -i http://download.openvz.org/kernel/branches/rhel6-2.6.32/042stab142.1/vzkernel-devel-2.6.32-042stab142.1.x86_64.rpm
rpm -i http://download.openvz.org/kernel/branches/rhel6-2.6.32/042stab142.1/vzkernel-headers-2.6.32-042stab142.1.x86_64.rpm
VBOX_VERSION=$(cat /home/vagrant/.vbox_version)
cd /tmp
mount -o loop /home/vagrant/VBoxGuestAdditions_${VBOX_VERSION}.iso /mnt
sh /mnt/VBoxLinuxAdditions.run
umount /mnt
rm -rf /home/vagrant/VBoxGuestAdditions_${VBOX_VERSION}.iso
