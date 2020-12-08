#!/bin/sh

MYSQL_ROOT_PW=vagrant
MYSQL_ROOT_CONFIG_PATH=/root/.my.cnf

# Disable SELinux
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config


# Add repos
yum -y install epel-release centos-release-scl-rh
rpm -Uvh http://packages.hubzero.org/rpm/julian-el7/hubzero-release-julian-2.2.7-1.el7.noarch.rpm

yum -y update


# Disable yum fastestmirror plugin
sed -i 's/^enabled=1/enabled=0/' /etc/yum/pluginconf.d/fastestmirror.conf


# Utils
yum -y install lsof


# Firewall
yum -y remove firewalld

yum -y install hubzero-iptables-basic
service hubzero-iptables-basic start
chkconfig hubzero-iptables-basic on

yum -y install hubzero-mw2-iptables-basic
service hubzero-mw2-iptables-basic start
chkconfig hubzero-mw2-iptables-basic on


# Apache
yum -y install hubzero-apache2
service httpd start
chkconfig httpd on


# PHP
rpm -Uvh https://rpms.remirepo.net/enterprise/remi-release-7.rpm
yum -y install hubzero-php56-remi
service php56-php-fpm start
chkconfig php56-php-fpm on


# MariaDB
cat << EOF > /etc/yum.repos.d/mariadb-5.5.repo
# MariaDB 5.5 CentOS repository list
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/5.5/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
yum -y install MariaDB-server
service mysql start
chkconfig mysql on


# Postfix
yum -y install postfix
service postfix start
chkconfig postfix on


# CMS
yum -y install hubzero-cms-2.2 hubzero-texvc hubzero-textifier wkhtmltopdf


# Mailgateway
yum -y install hubzero-mailgateway


# TODO: Proper CentOS 7 tool usage with Docker instead of OpenVZ remains unclear
#       For now we install the same packages as CentOS 6 below

# OpenLDAP
yum -y install hubzero-openldap


# WebDAV
yum -y install hubzero-webdav


# Subversion
yum -y install hubzero-subversion


# Trac
yum -y install hubzero-trac


# Forge
yum -y install hubzero-forge


# Docker
curl -fsSL https://get.docker.com/ | sh
systemctl start docker
systemctl enable docker
usermod -aG docker vagrant
curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose


# Maxwell File Service
yum -y install hubzero-mw2-file-service


# Maxwell Service
yum -y install hubzero-mw2-exec-service


# Maxwell Client
yum -y install hubzero-mw2-client
yum -y install hubzero-expire-sessions


# VNC Proxy Server
yum -y install hubzero-vncproxyd-ws


# Metrics
yum -y install hubzero-metrics


# telequotad
yum -y install hubzero-telequotad


# Workspace
yum -y install hubzero-app
yum -y install hubzero-app-workspace


# Rappture
# TODO: Determine how handled w/o OpenVZ
#yum -y install hubzero-rappture-deb7


# Filexfer
yum -y install hubzero-filexfer-xlate


# Submit
yum -y install hubzero-submit-pegasus
yum -y install hubzero-submit-condor
yum -y install hubzero-submit-common
yum -y install hubzero-submit-server
yum -y install hubzero-submit-distributor
yum -y install hubzero-submit-monitors


# Solr
yum -y install hubzero-solr


# Java
yum -y install java-1.8.0-openjdk


# Fake CA/cert generator
yum -y install golang
git clone git://github.com/jsha/minica.git minica
cd minica
go build
yum -y remove golang
rm -rf ~root/go
