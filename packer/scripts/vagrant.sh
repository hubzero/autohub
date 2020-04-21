date > /etc/vagrant_box_build_time
cd ~vagrant
mkdir -m 0700 .ssh
curl -L https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub -o .ssh/authorized_keys
chmod 0600 .ssh/authorized_keys
chown -R vagrant:vagrant .
