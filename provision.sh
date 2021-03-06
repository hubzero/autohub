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
function init_vars {
    # Dir for minica (fake certificate authority util)
    MINICA_DIR=/home/vagrant/minica

    # Directory certificates are stored in
    CERT_DIR=/etc/ssl/certs

    # Directory private keys for certificates are stored in
    KEY_DIR=/etc/pki/tls/private

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

    # Webroot for hub
    HUBROOT=/var/www/${HUBNAME}


    # Provision options
    YUM_UPDATE=true
    CHECK_OLD_DATA=true
    TOOLS_ENABLED=false

    # URL for installation documentation (used in INFO & ERROR messages)
    INSTALLATION_DOC_URL=https://help.hubzero.org/documentation/22/installation/centos7
}


function override_vars {
    if [[ -f vars.sh ]]; then
        . vars.sh
    fi
}


##############################################################################
#
# Guard against old data
#

function check_old_data {
    echo "[INFO] Checking for orphaned webroot and database data"
    NUM_WEB_FILES=$(find ${GUEST_SHARE_DIR}/webroot -type f -not -name '.keep' | wc -l)
    NUM_DB_FILES=$(find ${GUEST_SHARE_DIR}/db -type f -not -name '.keep' | wc -l)
    if (( $NUM_WEB_FILES > 0 )); then
        echo "[WARN] Non-empty webroot found at ${HOST_SHARE_DIR}/webroot"
    fi
    if (( $NUM_DB_FILES > 0 )); then
        echo "[WARN] Non-empty database found at ${HOST_SHARE_DIR}/db"
    fi
    if (( $NUM_WEB_FILES > 0 || $NUM_DB_FILES > 0 )); then
        echo "[ERROR] Not overwriting orphaned data; please delete or move the data"
        echo "[ERROR] Running the script \`./delete-cms-data.sh\` will delete the data for you."
        echo "[ERROR] Afteward run \`vagrant destroy -f && vagrant up\` afterward to recreate the VM"
        exit 1
    else
        echo "[INFO] No orphaned data found"
    fi
}


##############################################################################
#
# SSH keypair
#

function configure_ssh_keypair {
    SSH_KEY_TYPE=rsa
    SSH_KEY_FN=id_${SSH_KEY_TYPE}
    SSH_KEY_PATH=~vagrant/.ssh/${SSH_KEY_FN}
    SHARED_SSH_KEY_PATH="${GUEST_SHARE_DIR}/${SSH_KEY_FN}"
    if [[ -f ${SHARED_SSH_KEY_PATH} && -f ${SHARED_SSH_KEY_PATH}.pub ]]; then
        echo "[INFO] Using existing SSH keypair"
        cp -f "${SHARED_SSH_KEY_PATH}" "${SSH_KEY_PATH}"
        cp -f "${SHARED_SSH_KEY_PATH}.pub" "${SSH_KEY_PATH}.pub"
        chmod -f 0600 "${SSH_KEY_PATH}"
        chmod -f 0644 "${SSH_KEY_PATH}.pub"
        chown -f vagrant:vagrant "${SSH_KEY_PATH}"
        chown -f vagrant:vagrant "${SSH_KEY_PATH}.pub"
    else
        echo "[INFO] Creating SSH keypair"
        rm -f "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
        ssh-keygen -f "${SSH_KEY_PATH}" -t ${SSH_KEY_TYPE} -N ''
        chown -f vagrant:vagrant "${SSH_KEY_PATH}"
        chown -f vagrant:vagrant "${SSH_KEY_PATH}.pub"
        cp -f "${SSH_KEY_PATH}" "${SHARED_SSH_KEY_PATH}"
        cp -f "${SSH_KEY_PATH}.pub" "${SHARED_SSH_KEY_PATH}.pub"
    fi
}


##############################################################################
#
# Pre-check
#

function precheck {
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
    hostnamectl set-hostname ${HOSTNAME}
    echo "[INFO] Hostname is '${HOSTNAME}'"

    # Set MySQL root password
    LOCAL_MYSQL_CONF=/root/.my.cnf
    mysqladmin -u root password "${DB_ROOT_PASSWORD}"
    echo -e "[client]\nuser=root\npassword=${DB_ROOT_PASSWORD}\n" > ${LOCAL_MYSQL_CONF}
    chmod -f 0600 ${LOCAL_MYSQL_CONF}

    # TODO: Remove from here after moving to Packer script
    # Remove old PHP
    yum -y remove php-cli php-common
    ln -sf /opt/remi/php56/root/bin/php /usr/bin/php

    # Update packages
    if [ "${YUM_UPDATE}" = true ]; then
        echo "[INFO] Updating packages"
        yum -y update
    else
        echo "[SKIP] Not updating packages"
    fi
}


##############################################################################
#
# Postfix
#

function check_postfix {
    postfix check
    if (( $? == 0 )); then
            echo "[INFO] No issues detected with Postfix"
    else
        echo "[ERROR] Problem(s) found with Postfix"
            echo "[ERROR] * See ${INSTALLATION_DOC_URL}/install/mail"
            exit 1
    fi
}


##############################################################################
#
# CMS
#

function set_mysql_password {
    systemctl stop mysql
    systemctl start mysql
    systemctl stop mysql

    /usr/bin/mysqld_safe --skip-grant-tables --skip-networking --skip-syslog &

    MYSQL_PASSWORD_CHANGE_PATH=/tmp/pw.sql
    cat <<EOT > ${MYSQL_PASSWORD_CHANGE_PATH}
USE mysql;
UPDATE user SET password=PASSWORD('${CMS_DB_PASSWORD}') WHERE user='${HUBNAME}';
FLUSH PRIVILEGES;
EOT
    mysql -u root < ${MYSQL_PASSWORD_CHANGE_PATH}
    rm -f ${MYSQL_PASSWORD_CHANGE_PATH}
    mysqladmin -u root shutdown
    systemctl start mysql

    VAGRANT_MYSQL_CONF=~vagrant/.my.cnf
    echo -e "[client]\nuser=${HUBNAME}\npassword=${CMS_DB_PASSWORD}\n" > ${VAGRANT_MYSQL_CONF}
    chmod -f 0600 ${VAGRANT_MYSQL_CONF}

    # Seems to not start sometimes
    systemctl restart mysql
    sleep 2
}

function configure_cms {
    echo "[INFO] Setting up hub"
    if [[ ! -z "${CMS_ADMIN_PASSWORD}" ]]; then
            echo -n ${CMS_ADMIN_PASSWORD} > /etc/hubzero-adminpw
        chmod -f 0600 /etc/hubzero-adminpw
    fi
    if [[ ! -z "${HUB_UPSTREAM_URL}" ]]; then
        echo "[INFO] Getting hub code from remote"
        HUBZERO_CMS_DIR=/usr/share/hubzero-cms-git/cms
        mkdir -p ${HUBZERO_CMS_DIR}
        if [[ ! -z "${GIT_USERNAME}" ]]; then
            git config --global user.name "${GIT_USERNAME}"
            echo "[INFO] Global git username set to '${GIT_USERNAME}'"
        fi
        if [[ ! -z "${GIT_EMAIL}" ]]; then
            git config --global user.email "${GIT_EMAIL}"
            echo "[INFO] Global git email set to '${GIT_EMAIL}'"
        fi
        git clone ${HUB_UPSTREAM_URL} --branch ${HUB_UPSTREAM_BRANCH} ${HUBZERO_CMS_DIR}
        cd ${HUBZERO_CMS_DIR}
        git remote rename origin upstream
        git remote add origin ${HUB_ORIGIN_URL}
        DOTGIT_BACKUP_DIR=${HUBZERO_CMS_DIR}/.git-BAK
        # hzcms shirks its duty if `.git/` exists
        mv -f ${HUBZERO_CMS_DIR}/.git ${DOTGIT_BACKUP_DIR}
    else
        echo "[INFO] Using hub code from package manager"
    fi

    hzcms install ${HUBNAME}

    # Remove toolgit so `hzcms update` runs properly
    rm -rf /var/www/.ssh-toolgit/toolgit_rsa

    hzcms update

    if [[ ! -z "${HUB_UPSTREAM_URL}" ]]; then
        # Restore `.git/`
        mv -f ${DOTGIT_BACKUP_DIR} ${HUBZERO_CMS_DIR}/.git
        cp -r ${HUBZERO_CMS_DIR}/.git ${HUBROOT}/

        # Start with a clean slate
        echo "[INFO] Stashing changes"
        cd ${HUBROOT}
        git stash
        git stash clear

        # Remove friction from making changes to files
        chown -fR apache:vagrant ${HUBROOT}
        chown -fR apache:vagrant ${HUBROOT}/.*
        chmod -fR g+w ${HUBROOT}
        chmod -fR g+w ${HUBROOT}/.*

        # Appease `hubzero-app`
        chgrp -f apache ${HUBROOT}/configuration.php
    fi

    # Reset CMS passwords
    if [[ ! -z "${CMS_DB_PASSWORD}" ]]; then
        set_mysql_password
    fi
    OLD_CMS_DB_PASSWORD=$(egrep -o '^HUBDB=.*$' /etc/hubzero.secrets | cut -d= -f2)
    echo ${OLD_CMS_DB_PASSWORD} > /home/vagrant/old-db-pw
    sed -ri 's/(HUBDB=)'${OLD_CMS_DB_PASSWORD}'/\1'${CMS_DB_PASSWORD}'/' /etc/hubzero.secrets
    sed -ri "s/(\\\$password = ')${OLD_CMS_DB_PASSWORD}(';\$)/\1${CMS_DB_PASSWORD}\2/" ${HUBROOT}/configuration.php /etc/hubmail_gw.conf
    sed -ri "s/('password' => ')${OLD_CMS_DB_PASSWORD}(',)/\1${CMS_DB_PASSWORD}\2/" ${HUBROOT}/config/database.php

    mysql -u root -p${DB_ROOT_PASSWORD} ${HUBNAME} <<EOT
UPDATE jos_extensions
 SET params=REPLACE(params,'"statsDBPassword":"${OLD_CMS_DB_PASSWORD}"','"statsDBPassword":"${CMS_DB_PASSWORD}"')
WHERE name='com_usage';
EOT

    # Replicate config under `app`
    echo "[INFO] Copying configuration to app directory"
    mkdir -p ${HUBROOT}/app/config
    find ${HUBROOT}/config -type f -exec cp -f {} ${HUBROOT}/app/config/ \;

    # Create certs
    HOST_CA_CERT_PATH="${HOST_SHARE_DIR}/ca.crt"
    HOST_CA_KEY_PATH="${HOST_SHARE_DIR}/ca.key"
    GUEST_CA_KEY_PATH="${GUEST_SHARE_DIR}/ca.key"
    GUEST_CA_CERT_PATH="${GUEST_SHARE_DIR}/ca.crt"
    MINICA_CERT="${MINICA_DIR}/minica.pem"
    MINICA_KEY="${MINICA_DIR}/minica-key.pem"
    if [[ -f "${GUEST_CA_KEY_PATH}" && -f "${GUEST_CA_CERT_PATH}" ]]; then
        echo "[INFO] Using existing certificate authority to create cert for host' ${HOSTNAME}'"
        EXISTING_CA=true
        cp -f ${GUEST_CA_KEY_PATH} ${MINICA_KEY}
        cp -f ${GUEST_CA_CERT_PATH} ${MINICA_CERT}
    else
        echo "[INFO] Creating new fake certificate authority and cert for host '${HOSTNAME}'"
        EXISTING_CA=false
    fi
    cd ${MINICA_DIR}
    ${MINICA_DIR}/minica --domains ${HOSTNAME}
    HOST_CA_CERT_PATH="${HOST_SHARE_DIR}/ca.crt"
    cp -f ${MINICA_KEY} ${CA_KEY_PATH}
    cp -f ${MINICA_CERT} ${CA_CERT_PATH}
    cp -f ${MINICA_KEY} "${GUEST_CA_KEY_PATH}"
    cp -f ${MINICA_CERT} "${GUEST_CA_CERT_PATH}"
    chmod -f 0640 ${CA_CERT_PATH}
    chmod -f 0640 ${CA_KEY_PATH}
    chmod -f 0640 ${GUEST_CA_KEY_PATH}
    chmod -f 0640 ${GUEST_CA_CERT_PATH}
    cd ~vagrant

    # Install CA locally
    echo "[INFO] Installing certificate authority"
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
    APACHELINE=$(grep -n -E 'ProxyPassMatch.*?php' /etc/httpd/sites-m4/${HUBNAME}-ssl.m4 | cut -f1 -d:)
    sed -i "${APACHELINE} a \ \ \ \ \ \ \ \ SetEnvIf Authorization \"(.*)\" HTTP_AUTHORIZATION=\$1" /etc/httpd/sites-m4/${HUBNAME}-ssl.m4

    # Not sure why we have to run this twice
    hzcms update

    hzcms reconfigure ${HUBNAME}

    systemctl restart httpd
}


##############################################################################
#
# LDAP
#

function configure_ldap {
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
}


##############################################################################
#
# WebDAV
#

function configure_webdav {
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
}


##############################################################################
#
# Mailgateway
#

function configure_mailgateway {
    echo "[INFO] Configuring Mailgateway"
    hzcms configure mailgateway --enable
}


##############################################################################
#
# Subversion
#

function configure_subversion {
    echo "[INFO] Configuring Subversion"
    hzcms configure subversion --enable
}


##############################################################################
#
# Trac
#

function configure_trac {
    echo "[INFO] Configuring Trac"
    hzcms configure trac --enable
}


##############################################################################
#
# Forge
#

function configure_forge {
    echo "[INFO] Configuring Forge"
    hzcms configure forge --enable
}


##############################################################################
#
# Set up OpenVZ
#

function configure_openvz {
    hzcms configure openvz --enable
    vzlist 2>&1 > /dev/null | grep -q 'Container(s) not found'
    if (( $? == 0 )); then
            echo "[INFO] Verified OpenVZ is working"
    else
            echo "[ERROR] Problems found with OpenVZ"
            echo "[ERROR] * See ${INSTALLATION_DOC_URL}/install/openvz"
            exit 1
    fi
}


##############################################################################
#
# Maxwell Client
#

function configure_maxwell_client {
    echo "[INFO] Configuring Maxwell Client"
    hzcms configure mw2-client --enable
}


##############################################################################
#
# Maxwell Service
#

function configure_maxwell_service {
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
        echo "[ERROR] * See ${INSTALLATION_DOC_URL}/install/maxwell_service"
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
        echo "[ERROR] * See ${INSTALLATION_DOC_URL}/install/maxwell_service"
        exit 1
    fi

    maxwell_service stopvnc ${MW_TEST_CTID}
    grep -q ' is unmounted' /var/log/mw-service/service.log
    if (( $? == 0 )); then
        echo "[INFO] Successfully shut down session"
    else
        echo "[ERROR] Failed to shut down session"
        echo "[ERROR] * See ${INSTALLATION_DOC_URL}/install/maxwell_service"
        vzlist
        exit 1
    fi
    rm -f ${MW_TEST_LOG}
}


##############################################################################
#
# VNC proxy
#

function configure_vncproxy {
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
}


##############################################################################
#
# telequotad
#

function check_telequotad {
    echo "[INFO] Checking quotas"
    LINES=$(repquota -a | wc -l)
    if (( ${LINES} > 0 )); then
        echo "[INFO] Quotas appear to be enabled"
    else
        echo "[ERROR] Quotas don't seem to be set"
            echo "[ERROR] * See ${INSTALLATION_DOC_URL}/install/telequotad"
            exit 1
    fi
}


##############################################################################
#
# Workspace
#

function configure_workspace {
    echo "[INFO] Installing Workspace"
    hubzero-app install --publish /usr/share/hubzero/apps/workspace-1.3.hza
    # TODO: ensure 'Workspace' appears on website tools
}


##############################################################################
#
# FileXfer
#

function configure_filexfer {
    echo "[INFO] Configuring FileXfer"
    hzcms configure filexfer --enable
}


##############################################################################
#
# Rappture
#

function configure_rappture {
    echo "[INFO] Rappture is already configured"
    echo "[INFO] * A workspace may need to be opened and closed a few times before"
    echo "[INFO] the changes to the session template appear in a workspace."
    echo "[INFO] Further manual testing is required"
    echo "[INFO] * See ${INSTALLATION_DOC_URL}/install/rappture"
}


##############################################################################
#
# Submit
#

function configure_submit {
    echo "[INFO] Configuring Submit"
    hzcms configure submit-server --enable
}


##############################################################################
#
# Solr
#

function configure_solr {
    echo "[INFO] Starting Solr"
    service hubzero-solr start
    chkconfig hubzero-solr on
}


##############################################################################
#
# Shibboleth
#

function configure_shibboleth {
    echo "[INFO] Nothing implemented yet for Shibboleth"
    # TODO: implement
}


##############################################################################
#
# PHP debugging support
#

function configure_php_debugging {
    PHP_ROOT='/opt/remi/php56/root'
    PHP_INI_PATH="${PHP_ROOT}/etc/php.ini"
    HOST_IP=$(echo $SSH_CLIENT | cut -d' ' -f1)
    cat <<EOT >> ${PHP_INI_PATH}

;; Added by autohub
[xdebug]
xdebug.remote_enable=1
xdebug.remote_host='${HOST_IP}'
xdebug.remote_port=9000
xdebug.remote_connect_back=1
xdebug.remote_autostart=1
xdebug.idekey='${HUBNAME}'
EOT
}


##############################################################################
#
# Quality-of-life improvements
#

function configure_quality_of_life {
    cat <<EOT > /etc/motd
+------------------------------------------------------------------------
|
| '${HUBNAME}' DEVELOPMENT HUB
|
| Hub name:            ${HUBNAME}
| Hub hostname:        ${HOSTNAME}
| Document root:       $(grep documentroot /etc/hubzero.conf | awk '{print $3}')
| CMS admin user:      ${CMS_ADMIN_USER}
| CMS admin password:  ${CMS_ADMIN_PASSWORD}
| MySQL root password: ${DB_ROOT_PASSWORD}
| MySQL CMS user:      ${HUBNAME}
| MySQL CMS password:  ${CMS_DB_PASSWORD}
| php.ini location:    ${PHP_INI_PATH}
|
| Operating system:    $(cat /etc/centos-release)
| Docker:              $(docker --version)
| docker-compose:      $(/usr/local/bin/docker-compose --version)
| Java:                $(java -version 2>&1 /dev/null | head -2 | tail -1)
| Apache:              $(httpd -version | head -1 | sed -e 's/^.\+: //')
| PHP:                 $(php --version | head -1)
| MySQL:               $(mysql --version | sed 's/, .\+$//')
|
| * These are initial values; changes you make won't be reflected here
| * Edit '/etc/motd' to make changes
|
+------------------------------------------------------------------------
EOT
}


##############################################################################
#
# Finished; closing notes
#

function show_closing_message {
    echo "[INFO] ==(( ACTION REQUIRED ))================================================"
    if [ "${EXISTING_CA}" = true ]; then
        echo "[INFO]"
        echo "[INFO] * If not already done, import the CA certificate below into your client browser(s)"
    else
        echo "[INFO] * Import the fake CA certificate below into your client browser(s)"
    fi
    echo "[INFO]"
    echo "[INFO]   Certificate authority keys are here on the host machine:"
    echo "[INFO]"
    echo "[INFO]     - '${HOST_CA_CERT_PATH}' (private key)"
    echo "[INFO]     - '${HOST_CA_KEY_PATH}' (public key)"
    echo "[INFO]"
    CA_ISSUER=$(openssl x509 -noout -issuer -in ${MINICA_CERT} | cut -d= -f3)
    echo "[INFO]   CA issuer (will display in browser): '${CA_ISSUER}'"
    echo "[INFO]"
    echo "[INFO] ==(( ACTION REQUIRED ))================================================"
    echo "[INFO]"
    echo "[INFO] * Add '${HOSTNAME} 127.0.0.1' to your host machine's"
    echo "[INFO]"
    echo "[INFO]   '/etc/hosts' for the TLS cert to be accepted; e.g.:"
    echo "[INFO]   $ echo 'echo 127.0.0.1 ${HOSTNAME} >> /etc/hosts' | sudo sh"
    echo "[INFO]"
    echo "[INFO] ==(( ACTION REQUIRED ))================================================"
    echo "[INFO]"
    echo "[INFO] * Add the public SSH key to GitHub/GitLab/etc. to allow pushing code"
    echo "[INFO]"
    echo "[INFO]   SSH keypair is here on the host machine:"
    echo "[INFO]     - '${HOST_SHARE_DIR}/${SSH_KEY_FN}' (private key)"
    echo "[INFO]     - '${HOST_SHARE_DIR}/${SSH_KEY_FN}.pub' (public key)"
    echo "[INFO]"
    echo "[INFO] ==(( ACTION REQUIRED ))================================================"
    echo "[INFO]"
    echo "[INFO] * Setup remote PHP debugging:"
    echo "[INFO]"
    echo "[INFO]   - See README.md for instructions"
    echo "[INFO]   - You may have to set your IDE key to '${HUBNAME}'"
    echo "[INFO]"
    if [ "${SOLR_ENABLED}" = true ]; then
        echo "[INFO] ==(( ACTION REQUIRED ))================================================"
        echo "[INFO]"
        echo "[INFO] * Finish setting up Solr"
        echo "[INFO]"
        echo "[INFO]   - See ${INSTALLATION_DOC_URL}/addons/solr"
        echo "[INFO]"
    fi
    echo "[INFO] ==(( ACTION REQUIRED ))================================================"
    echo "[INFO]"
    echo "[INFO] * Finish setting up Submit"
    echo "[INFO]"
    echo "[INFO]   - See ${INSTALLATION_DOC_URL}/install/submit"
    echo "[INFO]"
    echo "[INFO] ***********************************************************************"
    echo "[INFO]"
    echo "[INFO] Hub setup is complete"
}


##############################################################################
#
# Main provision flow
#

function main {
    init_vars
    override_vars

    if [ "${CHECK_OLD_DATA}" = true ]; then
        check_old_data
    else
        echo "[SKIP] Not checking for orphaned webroot or database data"
    fi

    configure_ssh_keypair
    precheck
    check_postfix
    configure_cms
    configure_mailgateway

    if [ "${TOOLS_ENABLED}" = true ]; then
        configure_ldap
        configure_webdav
        configure_subversion
        configure_trac
        configure_forge
        configure_openvz
        configure_maxwell_client
        configure_maxwell_service
        configure_vncproxy
        check_telequotad
        configure_workspace
        configure_filexfer
        configure_rappture
        configure_submit
    else
        echo "[SKIP] Not enabling infrastructure for tools"
    fi

    if [ "${SOLR_ENABLED}" = true ]; then
        configure_solr
    else
        echo "[SKIP] Solr option is disabled; skipping"
    fi

    if [ "${TOOLS_ENABLED}" = true ]; then
        configure_shibboleth
    else
        echo "[SKIP] Shibboleth option is disabled; skipping"
    fi

    configure_php_debugging
    configure_quality_of_life
    show_closing_message
}


main
