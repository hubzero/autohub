#!/bin/bash

set -o nounset
set -o pipefail
set -o noglob

# Uncomment to debug
#set -x


##############################################################################
#
# Varibles/config
#

# Internal vars

# Dir for minica (fake certificate authority util)
MINICA_DIR=/home/vagrant/minica

# Directory certificates are stored in
CERT_DIR=/etc/ssl/certs

# Directory private keys for certificates are stored in
KEY_DIR=/etc/ssl/certs/private

# Path to fake cert authority cert
CA_CERT_PATH=${CERT_DIR}/${HUBNAME}-fake-ca.pem

# Path to fake cert authority private key
CA_KEY_PATH=${KEY_DIR}/${HUBNAME}-fake-ca-key.pem

# Path to fake hub cert
CMS_CERT_PATH=${CERT_DIR}/${HUBNAME}-fake-cert.pem

# Path to fake hub cert private key
CMS_KEY_PATH=${KEY_DIR}/${HUBNAME}-fake-cert-key.pem

# Override for bug in `/usr/sbin/hubzero-mw2-iptables-basic` regex
EXT_DEV=$(ip route ls | grep default | awk '{print $5}')


# Optional variable overrides
if [[ -f vars.sh ]]; then
	. vars.sh
fi


##############################################################################
#
# Pre-check
#

# Get hubname
if [[ -z "${HUBNAME:-}" ]]; then
        echo "[ERROR] Hub name must be set in \$HUBNAME"
        exit 1
fi

echo "[INFO] Hub name is '${HUBNAME}'"

if [[ ! ${HUBNAME^^} =~ ^[A-Z][A-Z0-9]*$ ]]; then
        echo "[ERROR] Hub name must alphanumeric and begin with a letter"
        exit 1
fi

# Set hostname
hostname --file /etc/hostname
grep -q "HOSTNAME=${HOSTNAME}" /etc/sysconfig/network
if (( $? == 0 )); then
	echo "[INFO] Hostname is '${HOSTNAME}'"
else
	exit 1
fi

# Set MySQL root password
LOCAL_MYSQL_CONF=/root/.my.cnf
mysqladmin -u root password "${DB_ROOT_PASSWORD}"
echo -e "[client]\nuser=root\npassword=${DB_ROOT_PASSWORD}\n" > ${LOCAL_MYSQL_CONF}
chmod -f 0600 ${LOCAL_MYSQL_CONF}


##############################################################################
#
# Postfix
#

postfix check
if (( $? == 0 )); then
        echo "[INFO] No issues detected with Postfix"
else
	echo "[ERROR] Problem(s) found with Postfix"
        echo "        * See https://help.hubzero.org/documentation/22/installation/redhat/install/mail"
        exit 1
fi


##############################################################################
#
# CMS
#

echo "[INFO] Setting up hub"
if [[ ! -z "${CMS_ADMIN_PASSWORD}" ]]; then
        echo -n ${CMS_ADMIN_PASSWORD} > /etc/hubzero-adminpw
	chmod -f 0600 /etc/hubzero-adminpw
fi
if [[ ! -z "${HUB_SOURCE_URL}" ]]; then
	echo "[INFO] Getting hub code from remote"
	HUBZERO_CMS_DIR=/usr/share/hubzero-cms-git/cms
	mkdir -p ${HUBZERO_CMS_DIR}
	git clone ${HUB_SOURCE_URL} ${HUBZERO_CMS_DIR}
	DOTGIT_BACKUP_DIR=${HUBZERO_CMS_DIR}/.git-BAK
	# hzcms shirks its duty if `.git/` exists
	mv -f ${HUBZERO_CMS_DIR}/.git ${DOTGIT_BACKUP_DIR}
fi
hzcms install ${HUBNAME}
hzcms update
if [[ ! -z "${HUB_SOURCE_URL}" ]]; then
	# Restore `.git/`
	mv -f ${DOTGIT_BACKUP_DIR} ${HUBZERO_CMS_DIR}/.git
	cp -r ${HUBZERO_CMS_DIR}/.git /var/www/${HUBNAME}/

	# Remove friction from making changes to files
	chown -fR apache:vagrant /var/www/${HUBNAME}
	chmod -fR g+w /var/www/${HUBNAME}

	# Appease `hubzero-app`
	chgrp -f apache /var/www/${HUBNAME}/configuration.php

	# Start with a clean slate
	cd /var/www/${HUBNAME}
	git stash
	git stash clear
fi

# Reset CMS passwords
if [[ ! -z "${CMS_DB_PASSWORD}" ]]; then
        hzcms resetmysqlpw --username ${HUBNAME} --pw "${CMS_DB_PASSWORD}"
fi
OLD_CMS_DB_PASSWORD=$(egrep -o '^HUBDB=.*$' /etc/hubzero.secrets | cut -d= -f2)
echo ${OLD_CMS_DB_PASSWORD} > /home/vagrant/old-db-pw
sed -ri 's/(HUBDB=)'${OLD_CMS_DB_PASSWORD}'/\1'${CMS_DB_PASSWORD}'/' /etc/hubzero.secrets
sed -ri "s/(\\\$password = ')${OLD_CMS_DB_PASSWORD}(';\$)/\1${CMS_DB_PASSWORD}\2/" /var/www/${HUBNAME}/configuration.php /etc/hubmail_gw.conf
sed -ri "s/('password' => ')${OLD_CMS_DB_PASSWORD}(',)/\1${CMS_DB_PASSWORD}\2/" /var/www/${HUBNAME}/config/database.php

mysql -u root -p${DB_ROOT_PASSWORD} ${HUBNAME} <<EOT
UPDATE jos_extensions
 SET params=REPLACE(params,'"statsDBPassword":"${OLD_CMS_DB_PASSWORD}"','"statsDBPassword":"${CMS_DB_PASSWORD}"')
WHERE name='com_usage';
EOT

# Create certs
echo "[INFO] Creating certificate authority and cert for host '${HOSTNAME}'"
cd ${MINICA_DIR}
${MINICA_DIR}/minica --domains ${HOSTNAME}
GUEST_CA_CERT_BASEPATH="${GUEST_SHARE_DIR}/${HUBNAME}-fake-ca"
HOST_CA_CERT_BASEPATH="${HOST_SHARE_DIR}/${HUBNAME}-fake-ca"
cp -f ${MINICA_DIR}/minica-key.pem ${CA_KEY_PATH}
chmod 0640 ${CA_KEY_PATH}
cp -f ${MINICA_DIR}/minica.pem ${CA_CERT_PATH}
chmod 0640 ${CA_CERT_PATH}
cp -f ${MINICA_DIR}/minica.pem "${GUEST_CA_CERT_BASEPATH}.crt"
cd ~vagrant

# Install CA locally
echo "[INFO] Installing fake certificate authority"
cp -f ${MINICA_DIR}/minica.pem /etc/pki/ca-trust/source/anchors/${HUBNAME}-fake-ca.pem
update-ca-trust force-enable
update-ca-trust

# Make Apache use cert
echo "[INFO] Adding cert to Apache/HUBzero"
cp -f ${MINICA_DIR}/${HOSTNAME}/key.pem ${CMS_KEY_PATH}
chmod -f 0640 ${CMS_KEY_PATH}
cp -f ${MINICA_DIR}/${HOSTNAME}/cert.pem ${CMS_CERT_PATH}
chmod -f 0644 ${CMS_CERT_PATH}
sed -ri "s#(SSLCertificateFile) SSLCERTFILE#\1 ${CMS_CERT_PATH}#" "/etc/httpd/sites-m4/${HUBNAME}-ssl.m4"
sed -ri "s#(SSLCertificateKeyFile) SSLCERTKEYFILE#\1 ${CMS_KEY_PATH}#" "/etc/httpd/sites-m4/${HUBNAME}-ssl.m4"
hzcms reconfigure ${HUBNAME}
# Sometimes it just won't die:
killall httpd; sleep 1
/etc/init.d/httpd restart


##############################################################################
#
# LDAP
#

echo "[INFO] Configuring LDAP"
hzldap init dc=${HUBNAME},dc=org
hzcms configure ldap --enable
hzldap syncusers

# Verify admin user exists
getent passwd | egrep -q "^${CMS_ADMIN_USER}:"
if (( $? == 0 )); then
        echo "[INFO] Verified '${CMS_ADMIN_USER}' user added"
else
        echo "[ERROR] '${CMS_ADMIN_USER}' user not found"
        exit 1
fi


##############################################################################
#
# WebDAV
#

echo "[INFO] Configuring WebDAV"
hzcms configure webdav --enable

# Ensure presence of fuse kernel mod
modprobe fuse
lsmod | egrep -q '^fuse '
if (( $? == 0 )); then
        echo "[INFO] 'fuse' kernel module is loaded"
else
        echo "[ERROR] fuse kernel module isn't loaded"
        exit 1
fi

# Test read via web
if [[ -d /webdav/home/${CMS_ADMIN_USER} ]]; then
        echo "[INFO] Verified WebDAV installed"
else
        echo "[ERROR] WebDAV not installed"
        exit 1
fi

echo 'world' > /webdav/home/${CMS_ADMIN_USER}/hello
curl --silent https://${CMS_ADMIN_USER}:${CMS_ADMIN_PASSWORD}@${HOSTNAME}/webdav/hello | egrep -q '^world$'
if (( $? == 0 )); then
        echo "[INFO] Verified WebDAV access via web works"
else
        echo "[ERROR] Couldn't access WebDAV via the web"
        exit 1
fi

# Test read via WebDAV client
yum -y install cadaver
echo -e "default\nlogin ${CMS_ADMIN_USER}\npasswd ${CMS_ADMIN_PASSWORD}" > /root/.netrc
echo 'cat hello' | cadaver https://${HOSTNAME}/webdav | egrep -q '^world$'
if (( $? == 0 )); then
        echo "[INFO] Verified WebDAV access via WebDAV client works"
else
        echo "[ERROR] Couldn't access WebDAV via a WebDAV client"
        exit 1
fi
rm -f /root/.netrc
rm -f /webdav/home/${CMS_ADMIN_USER}/hello
yum -y remove cadaver


##############################################################################
#
# Mailgateway
#

echo "[INFO] Configuring Mailgateway"
hzcms configure mailgateway --enable


##############################################################################
#
# Subversion
#

echo "[INFO] Configuring Subversion"
hzcms configure subversion --enable


##############################################################################
#
# Trac
#

echo "[INFO] Configuring Trac"
hzcms configure trac --enable


##############################################################################
#
# Forge
#

echo "[INFO] Configuring Forge"
hzcms configure forge --enable


##############################################################################
#
# Set up OpenVZ
#

hzcms configure openvz --enable
vzlist 2>&1 > /dev/null | grep -q 'Container(s) not found'
if (( $? == 0 )); then
        echo "[INFO] Verified OpenVZ is working"
else
        echo "[ERROR] Problems found with OpenVZ"
        echo "        * See https://help.hubzero.org/documentation/22/installation/redhat/install/openvz"
        exit 1
fi


##############################################################################
#
# Maxwell Client
#

echo "[INFO] Configuring Maxwell Client"
hzcms configure mw2-client --enable


##############################################################################
#
# Maxwell Service
#

echo "[INFO] Configuring Maxwell Service"
hzcms configure mw2-service --enable
hzcms mw-host add localhost up openvz pubnet sessions workspace fileserver

# Test launching, connecting, terminating
echo "[INFO] Testing Maxwell Service"

echo testtest | maxwell_service startvnc 1 800x600 24
vzlist 2>&1 > /dev/null | grep -q 'Container(s) not found'
if (( $? == 1 )); then
	echo "[INFO] Session appears to have launched properly"
else
	echo "[ERROR] Session failed to launch"
	echo "        * See https://help.hubzero.org/documentation/22/installation/redhat/install/maxwell_service"
	exit 1
fi

MW_TEST_LOG=mw-svc.log
MW_TEST_CTID=$(vzlist -H -o ctid -a | awk '{print $1}')
expect -c "send \003;" | openssl s_client -connect localhost:4001 >> ${MW_TEST_LOG} 2> /dev/null
OPENSSL_SUCCESS=$?
grep -q 'CONNECTED' ${MW_TEST_LOG}
if (( $OPENSSL_SUCCESS == 0 && $? == 0 )); then
	echo "[INFO] Able to connect to session VNC server"
else
	echo "[ERROR] Failed to connect to session VNC server"
	echo "        * See https://help.hubzero.org/documentation/22/installation/redhat/install/maxwell_service"
	exit 1
fi

maxwell_service stopvnc ${MW_TEST_CTID}
grep -q ' is unmounted' /var/log/mw-service/service.log
if (( $? == 0 )); then
	echo "[INFO] Successfully shut down session"
else
	echo "[ERROR] Failed to shut down session"
	echo "        * See https://help.hubzero.org/documentation/22/installation/redhat/install/maxwell_service"
	vzlist
	exit 1
fi
rm -f ${MW_TEST_LOG}


##############################################################################
#
# VNC proxy
#

echo "[INFO] Configuring VNC proxy server"
hzvncproxyd-ws-config configure --enable

# Install certs
PEM_PATH=/etc/hzvncproxyd-ws/ssl-cert-hzvncproxyd-ws.pem
KEY_PATH=/etc/hzvncproxyd-ws/ssl-cert-hzvncproxyd-ws.key
cp -f ${CMS_CERT_PATH} ${PEM_PATH}
chown -f hzvncproxy:hzvncproxy ${PEM_PATH}
chmod -f 0640 ${PEM_PATH}
cp -f ${CMS_KEY_PATH} ${KEY_PATH}
chown -f hzvncproxy:hzvncproxy ${KEY_PATH}
chmod -f 0640 ${KEY_PATH}
service hzvncproxyd-ws restart


##############################################################################
#
# telequotad
#

echo "[INFO] Checking quotas"
LINES=$(repquota -a | wc -l)
if (( ${LINES} > 0 )); then
	echo "[INFO] Quotas appear to be enabled"
else
	echo "[ERROR] Quotas don't seem to be set"
        echo "        * See https://help.hubzero.org/documentation/22/installation/redhat/install/telequotad"
        exit 1
fi


##############################################################################
#
# Workspace
#

echo "[INFO] Installing Workspace"
hubzero-app install --publish /usr/share/hubzero/apps/workspace-1.3.hza
# TODO: ensure 'Workspace' appears on website tools


##############################################################################
#
# FileXfer
#

echo "[INFO] Configuring FileXfer"
hzcms configure filexfer --enable


##############################################################################
#
# Rappture
#

echo "[INFO] Rappture is already configured"
echo "       * A workspace may need to be opened and closed a few times before"
echo "         the changes to the session template appear in a workspace."
echo "[INFO] Further manual testing is required"
echo "       * See https://help.hubzero.org/documentation/22/installation/redhat/install/rappture"


##############################################################################
#
# Submit
#

echo "[INFO] Configuring Submit"
hzcms configure submit-server --enable
echo "[INFO] Further manual configuration/testing is required"
echo "       * See https://help.hubzero.org/documentation/22/installation/redhat/install/submit"


##############################################################################
#
# Solr
#

if [[ "${SOLR_ENABLED}" = true ]]; then
	echo "[INFO] Starting Solr"
	service hubzero-solr start
	chkconfig hubzero-solr on
	echo "[INFO] Further configuration is required to use Solr search"
	echo "       * See https://help.hubzero.org/documentation/22/installation/redhat/addons/solr"
else
	echo "[INFO] Solr option is disabled; skipping"
fi


##############################################################################
#
# Shibboleth
#

echo "[INFO] Nothing implemented yet for Shibboleth"
# TODO: implement


##############################################################################
#
# Finished; closing notes
#
echo "[INFO] Import the fake CA certificate below into your client browser(s)"
cat ${GUEST_CA_CERT_BASEPATH}.crt
echo "[INFO] Available as a file here:"
echo "[INFO]     - '${HOST_CA_CERT_BASEPATH}.crt' (on host machine)"
echo "[INFO]     - '${GUEST_CA_CERT_BASEPATH}.crt' (on guest VM)"
