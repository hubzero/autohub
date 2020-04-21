#!/bin/sh

# Disable SELinux
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config

# Add HUBzero repos
rpm -Uvh http://packages.hubzero.org/rpm/julian-el6/hubzero-julian-repo-2.2.5-1.el6.noarch.rpm
cat > /etc/yum.repos.d/rh-php56.repo <<EOT
[hubzero-php56]
name=Hubzero PHP56
baseurl=http://packages.hubzero.org/rpm/rh-php56/6Server
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo
EOT

# Update and install some prereqs
yum -y update
yum -y install epel-release centos-release-scl-rh sudo dirmngr software-properties-common

# Disable yum fastestmirror plugin
sed -i 's/^enabled=1/enabled=0/' /etc/yum/pluginconf.d/fastestmirror.conf

# HUBzero firewall
yum -y install hubzero-iptables-basic
service hubzero-iptables-basic start
chkconfig hubzero-iptables-basic on

# HUBzero database
# TODO: Use MariaDB instead; was having issues with
#       `hzcms resetmysqlpw` so ignoring for now
#cat << EOF > /etc/yum.repos.d/mariadb-5.5.repo
## MariaDB 5.5 CentOS repository list
## http://downloads.mariadb.org/mariadb/repositories/
#[mariadb]
#name = MariaDB
#baseurl = http://yum.mariadb.org/5.5/centos6-amd64
#gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
#gpgcheck=1
#EOF
#yum -y install MariaDB-server
#service mysql start
#chkconfig mysql on
yum -y install hubzero-mysql
service mysqld start
chkconfig mysqld on
mysqladmin -u root password vagrant
echo -e "[client]\nuser=root\npassword=vagrant\n" > /root/.my.cnf
chmod 0600 /root/.my.cnf

# Mail
yum -y install postfix
service postfix start
chkconfig postfix on

# Web server
yum -y install postfix
yum install -y hubzero-apache2
service httpd start
chkconfig httpd on

# PHP
#yum install -y hubzero-php
#service rh-php56-php-fpm start
#chkconfig rh-php56-php-fpm on
rpm -Uvh https://rpms.remirepo.net/enterprise/remi-release-6.rpm
yum -y install hubzero-php56-remi
service php56-php-fpm start
chkconfig php56-php-fpm on

# CMS
yum -y install hubzero-cms-2.2

# Mailgateway
yum -y install hubzero-mailgateway

# LDAP
yum -y install authconfig
authconfig --update
yum -y install hubzero-openldap
service slapd start
chkconfig slapd on
chkconfig sssd on

# WebDAV
yum -y install hubzero-webdav

# Subversion
yum -y install hubzero-subversion

# Trac
yum -y install hubzero-trac

# Forge
yum -y install hubzero-forge

# OpenVZ
yum -y install hubzero-openvz-repo
yum -y install hubzero-openvz

# Maxwell Client
yum -y install hubzero-mw2-client
yum -y install hubzero-expire-sessions
service expire-sessions start
chkconfig expire-sessions on

# Maxwell File Service
yum -y install hubzero-mw2-file-service

# Maxwell Service
yum -y install hubzero-mw2-exec-service
yum -y install hubzero-mw2-iptables-basic
service hubzero-mw2-iptables-basic start
chkconfig hubzero-mw2-iptables-basic on
mkvztemplate amd64 wheezy ellie

# VNC proxy server
yum -y install hubzero-vncproxyd-ws
service hzvncproxyd-ws start
chkconfig hzvncproxyd-ws on

# telequotad
yum -y install hubzero-telequotad
service telequotad start
chkconfig telequotad on
sed -ri 's#(\s/\s.*?defaults)#\1,quota#' /etc/fstab
mount -oremount /
quotacheck -cugm /
quotacheck -avugm
quotaon -u /

# Workspace
yum -y install hubzero-app
yum -y install hubzero-app-workspace

# FileXfer
yum -y install hubzero-filexfer-xlate

# Rappture
yum -y install hubzero-rappture-deb7
chroot /var/lib/vz/template/debian-7.0-amd64-maxwell /bin/bash -x <<EOT
apt-get -y update && apt-get -y upgrade
apt-get install -y hubzero-rappture-session
EOT

# Submit
yum -y install hubzero-submit-pegasus hubzero-submit-condor hubzero-submit-common hubzero-submit-server hubzero-submit-distributor hubzero-submit-monitors
service submit-server start
chkconfig submit-server on

# Solr
yum -y install hubzero-solr
# NOTE: Not automatically started at boot
#service hubzero-solr start
#chkconfig hubzero-solr start

# Shibboleth
yum -y install hubzero-shibboleth

# Install fake CA/cert generator
yum -y install golang
git clone git://github.com/jsha/minica.git minica
cd minica
go build
yum -y remove golang
rm -rf ~root/go

