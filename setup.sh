#!/bin/bash

APADIR='/etc/apache2'
OLSDIR='/usr/local/lsws'
CERTDIR='/etc/ssl'
USER=''
GROUP=''
PHP_P='7'
PHP_S='4'
APACHE_HTTP_PORT='81'
APACHE_HTTPS_PORT='444'
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

echoY() {
    echo -e "\033[38;5;148m${1}\033[39m"
}
echoG() {
    echo -e "\033[38;5;71m${1}\033[39m"
}
echoR()
{
    echo -e "\033[38;5;203m${1}\033[39m"
}

change_owner(){
    chown -R ${USER}:${GROUP} ${1}
}

silent() {
  if [[ $debug ]] ; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

line_change(){
    LINENUM=$(grep -v '#' ${2} | grep -n "${1}" | cut -d: -f 1)
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        sed -i "${LINENUM}d" ${2}
        sed -i "${LINENUM}i${3}" ${2}
    fi  
}

backup_old(){
    if [ -f ${1} ] && [ ! -f ${1}_old ]; then
       mv ${1} ${1}_old
    fi
}

rm_old_pkg(){
    silent systemctl stop ${1}
    if [ ${OSNAME} = 'centos' ]; then     
        silent yum remove ${1} -y 
    else 
        silent apt remove ${1} -y 
    fi 
    if [ "$(systemctl is-active ${1})" != 'active' ]; then 
        echoG "[OK] remove ${1}"
    else 
        echoR "[Failed] remove ${1}"
    fi             
}

checkweb(){
    if [ ${1} = 'lsws' ] || [ ${1} = 'ols' ]; then
        ps -ef | grep lshttpd | grep -v grep >/dev/null 2>&1
    else
        ps -ef | grep "${1}" | grep -v grep >/dev/null 2>&1
    fi    
    if [ ${?} = 0 ]; then 
        echoG "${1} process is running!"
        echoG 'Stop web service temporary'
        if [ "${1}" = 'lsws' ]; then 
           PROC_NAME='lshttpd'
            silent ${LSDIR}/bin/lswsctrl stop
            ps aux | grep '[w]swatch.sh' >/dev/null 2>&1
            if [ ${?} = 0 ]; then
                kill -9 $(ps aux | grep '[w]swatch.sh' | awk '{print $2}')
            fi    
        elif [ "${1}" = 'ols' ]; then 
            PROC_NAME='lshttpd'
            silent ${OLSDIR}/bin/lswsctrl stop  
        elif [ "${1}" = 'httpd' ]; then
            PROC_NAME='httpd'
            silent systemctl stop ${PROC_NAME}
        elif [ "${1}" = 'apache2' ]; then
            PROC_NAME='apache2' 
            silent systemctl stop ${PROC_NAME}
        fi
        sleep 5
        if [ $(systemctl is-active ${PROC_NAME}) != 'active' ]; then 
            echoG "[OK] Stop ${PROC_NAME} service"
        else 
            echoR "[Failed] Stop ${PROC_NAME} service"
        fi 
    else 
        echoR '[ERROR] Failed to start the web server.'
        ps -ef | grep ${PROC_NAME} | grep -v grep
    fi 
}

check_os()
{
    OSTYPE=$(uname -m)
    MARIADBCPUARCH=
    if [ -f /etc/redhat-release ] ; then
        OSVER=$(cat /etc/redhat-release | awk '{print substr($4,1,1)}')
        if [ ${?} = 0 ] ; then
            OSNAMEVER=CENTOS${OSVER}
            OSNAME=centos
            rpm -ivh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el${OSVER}.noarch.rpm >/dev/null 2>&1
        fi
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
        wget -qO - http://rpms.litespeedtech.com/debian/enable_lst_debain_repo.sh | bash >/dev/null 2>&1
        UBUNTU_V=$(grep 'DISTRIB_RELEASE' /etc/lsb-release | awk -F '=' '{print substr($2,1,2)}')
        if [ ${UBUNTU_V} = 14 ] ; then
            OSNAMEVER=UBUNTU14
            OSVER=trusty
            MARIADBCPUARCH="arch=amd64,i386,ppc64el"
        elif [ ${UBUNTU_V} = 16 ] ; then
            OSNAMEVER=UBUNTU16
            OSVER=xenial
            MARIADBCPUARCH="arch=amd64,i386,ppc64el"
        elif [ ${UBUNTU_V} = 18 ] ; then
            OSNAMEVER=UBUNTU18
            OSVER=bionic
            MARIADBCPUARCH="arch=amd64"
        elif [ ${UBUNTU_V} = 20 ] ; then
            OSNAMEVER=UBUNTU20
            OSVER=bionic
            MARIADBCPUARCH="arch=amd64"            
        fi
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
        wget -O - http://rpms.litespeedtech.com/debian/enable_lst_debain_repo.sh | bash
        DEBIAN_V=$(awk -F '.' '{print $1}' /etc/debian_version)
        if [ ${DEBIAN_V} = 7 ] ; then
            OSNAMEVER=DEBIAN7
            OSVER=wheezy
            MARIADBCPUARCH="arch=amd64,i386"
        elif [ ${DEBIAN_V} = 8 ] ; then
            OSNAMEVER=DEBIAN8
            OSVER=jessie
            MARIADBCPUARCH="arch=amd64,i386"
        elif [ ${DEBIAN_V} = 9 ] ; then
            OSNAMEVER=DEBIAN9
            OSVER=stretch
            MARIADBCPUARCH="arch=amd64,i386"
        elif [ ${DEBIAN_V} = 10 ] ; then
            OSNAMEVER=DEBIAN10
            OSVER=buster
        fi
    fi
    if [ "${OSNAMEVER}" = "" ] ; then
        echoR "Sorry, currently script only supports Centos(7-8), Debian(7-10) and Ubuntu(14,16,18,20)."
        exit 1
    else
        if [ "${OSNAME}" = "centos" ] ; then
            echoG "Current platform is ${OSNAME} ${OSVER}" 
        else
            export DEBIAN_FRONTEND=noninteractive
            echoG "Current platform is ${OSNAMEVER} ${OSNAME} ${OSVER}."
        fi
    fi
}

path_update(){
    if [ "${OSNAME}" = "centos" ] ; then
        USER='apache'
        GROUP='apache'
        REPOPATH='/etc/yum.repos.d'
        APACHENAME='httpd'
        APADIR='/etc/httpd'
        RED_VER=$(rpm -q --whatprovides redhat-release)
    elif [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then
        USER='www-data'
        GROUP='www-data'
        REPOPATH='/etc/apt/sources.list.d'
        APACHENAME='apache2'
        FPMCONF="/etc/php/${PHP_P}.${PHP_S}/fpm/pool.d/www.conf"
    fi      
}

ubuntu_sysupdate(){
    echoG 'System update'
    silent apt-get update
    silent DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o Dpkg::Options::='--force-confdef' \
    -o Dpkg::Options::='--force-confold' upgrade
    silent DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o Dpkg::Options::='--force-confdef' \
    -o Dpkg::Options::='--force-confold' dist-upgrade        
}

centos_sysupdate(){
    echoG 'System update'
    silent yum update -y    
    setenforce 0
}    

gen_selfsigned_cert(){
    KEYNAME="${CERTDIR}/example.key"
    CERTNAME="${CERTDIR}/example.crt"

    openssl ecparam  -genkey -name prime256v1 -out ${KEYNAME}
    silent openssl req -x509 -nodes -days 365 -new -key ${KEYNAME} -out ${CERTNAME} <<csrconf
US
NJ
Virtual
Example
Testing
webadmin
.
.
.
csrconf
}

ubuntu_pkg_basic(){
    echoG 'Install basic packages'
    if [ ! -e /bin/wget ]; then 
        silent apt-get install lsb-release -y
        silent apt-get install curl wget -y
    fi
    silent apt-get install curl net-tools software-properties-common -y
}

centos_pkg_basic(){
    echoG 'Install basic packages'
    if [ ! -e /bin/wget ]; then 
        silent yum install epel-release -y
        silent yum update -y
        silent yum install curl yum-utils wget -y
    fi
    if [[ -z "$(rpm -qa epel-release)" ]]; then
        silent yum install epel-release -y
    fi
    if [ ! -e /usr/bin/yum-config-manager ]; then 
        silent yum install yum-utils -y
    fi
    if [ ! -e /usr/bin/curl ]; then 
        silent yum install curl -y
    fi    
}

ubuntu_install_apache(){
    echoG 'Install Apache Web Server'
    if [ -e /usr/sbin/${APACHENAME} ]; then 
        echoY "Remove existing ${APACHENAME}" 
        rm_old_pkg ${APACHENAME}  
    fi    
    yes "" | add-apt-repository ppa:ondrej/apache2 >/dev/null 2>&1
    if [ "$(grep -iR apache2 ${REPOPATH}/)" = '' ]; then 
        echoR '[Failed] to add APACHE2 repository'
    fi     
    silent apt-get update
    apt install ${APACHENAME} -y >/dev/null 2>&1
    systemctl start ${APACHENAME} >/dev/null 2>&1
    SERVERV=$(echo $(apache2 -v | grep version) | awk '{print substr ($3,8,9)}')
    checkweb ${APACHENAME}
    echoG "Version: apache ${SERVERV}"
}

centos_install_apache(){
    echoG 'Install Apache Web Server'
    if [ -e /usr/sbin/${APACHENAME} ]; then 
        echoY "Remove existing ${APACHENAME}" 
        rm_old_pkg ${APACHENAME}
        silent yum remove httpd* -y
        KILL_PROCESS ${APACHENAME}  
    fi    
    cd ${REPOPATH}
    if [ "${OSNAMEVER}" != "CENTOS8" ] ; then
        wget https://repo.codeit.guru/codeit.el`rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release)`.repo >/dev/null 2>&1 
    fi    
    silent yum install ${APACHENAME} mod_ssl -y
    sleep 1
    silent systemctl start ${APACHENAME}
    SERVERV=$(echo $(httpd -v | grep version) | awk '{print substr ($3,8,9)}')
    checkweb ${APACHENAME}
    echoG "Version: apache ${SERVERV}"
}

ubuntu_install_ols(){
    echoG 'Install openLiteSpeed Web Server'
    ubuntu_reinstall 'openlitespeed'
    wget -q -O - http://rpms.litespeedtech.com/debian/enable_lst_debian_repo.sh | bash >/dev/null 2>&1
    /usr/bin/apt ${OPTIONAL} install openlitespeed -y >/dev/null 2>&1
    ENCRYPT_PASS=$(${OLSDIR}/admin/fcgi-bin/admin_php* -q ${OLSDIR}/admin/misc/htpasswd.php ${ADMIN_PASS})
    echo "admin:${ENCRYPT_PASS}" > ${OLSDIR}/admin/conf/htpasswd
    SERVERV=$(cat ${OLSDIR}/VERSION)
    echoG "Version: openlitespeed ${SERVERV}"
    checkweb ols
}

centos_install_ols(){
    echoG 'Install openLiteSpeed Web Server'
    centos_reinstall 'openlitespeed'
    if [ ${OSVER} = 8 ]; then
        silent rpm -Uvh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el8.noarch.rpm
    else
        silent rpm -Uvh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el7.noarch.rpm
    fi    
    silent /usr/bin/yum ${OPTIONAL} openlitespeed -y
    ENCRYPT_PASS=$(${OLSDIR}/admin/fcgi-bin/admin_php* -q ${OLSDIR}/admin/misc/htpasswd.php ${ADMIN_PASS})
    echo "admin:${ENCRYPT_PASS}" > ${OLSDIR}/admin/conf/htpasswd
    SERVERV=$(cat ${OLSDIR}/VERSION)
    echoG "Version: openlitespeed ${SERVERV}"
    echo "Version: openlitespeed ${SERVERV}" >> ${SERVERACCESS}    
    checkweb ols
}

ubuntu_reinstall(){
    apt --installed list 2>/dev/null | grep ${1} >/dev/null
    if [ ${?} = 0 ]; then
        OPTIONAL='--reinstall'
    else
        OPTIONAL=''
    fi  
}

centos_reinstall(){
    rpm -qa | grep ${1} >/dev/null
    if [ ${?} = 0 ]; then
        OPTIONAL='reinstall'
    else
        OPTIONAL='install'
    fi  
}

ubuntu_install_php(){
    echoG 'Install PHP & Packages for LSWS'  
    ubuntu_reinstall "lsphp${PHP_P}${PHP_S}"    
    wget -qO - http://rpms.litespeedtech.com/debian/enable_lst_debain_repo.sh | bash >/dev/null 2>&1
    for PKG in '' -common -curl -json -modules-source -mysql -opcache -pspell -recode -sybase -tidy; do
        /usr/bin/apt ${OPTIONAL} install -y lsphp${PHP_P}${PHP_S}${PKG} >/dev/null 2>&1
    done
    echoG 'Install PHP & Packages for Apache'  
    ubuntu_reinstall "php${PHP_P}.${PHP_S}"
    for PKG in '' -bcmath -cli -common -curl -enchant -fpm -gd -gmp -json -mbstring -mysql -opcache \
        -pspell -readline -recode -soap -tidy -xml -xmlrpc -zip; do 
        /usr/bin/apt ${OPTIONAL} install -y php${PHP_P}.${PHP_S}${PKG} >/dev/null 2>&1
    done
    sed -i -e 's/extension=pdo_dblib.so/;extension=pdo_dblib.so/' \
        /usr/local/lsws/lsphp${PHP_P}${PHP_S}/etc/php/${PHP_P}.${PHP_S}/mods-available/pdo_dblib.ini
    sed -i -e 's/extension=shmop.so/;extension=shmop.so/' /etc/php/${PHP_P}.${PHP_S}/fpm/conf.d/20-shmop.ini
    if [ ${OSNAMEVER} != 'UBUNTU20' ]; then
        sed -i -e 's/extension=wddx.so/;extension=wddx.so/' /etc/php/${PHP_P}.${PHP_S}/fpm/conf.d/20-wddx.ini
    fi    
    NEWKEY='listen.backlog = 4096'
    line_change 'listen.backlog' ${FPMCONF} "${NEWKEY}"
}

centos_install_php(){
    echoG 'Install PHP & Packages'  
    /usr/bin/yum install -y http://rpms.remirepo.net/enterprise/remi-release-${OSVER}.rpm >/dev/null 2>&1
    /usr/bin/yum install -y yum-utils >/dev/null 2>&1
    /usr/bin/yum-config-manager --enable remi-php${PHP_P}${PHP_S} >/dev/null 2>&1
    for PKG in '' -common -pdo -gd -mbstring -mysqlnd -litespeed -opcache -pecl-zip -tidy -gmp -bcmath \
        -enchant -cli -json -xml -fpm -recode -soap -xmlrpc -sodium; do 
        /usr/bin/yum install php${PKG} -y >/dev/null 2>&1
    done
    sed -i -e 's/extension=bz2/;extension=bz2/' /etc/php.d/20-bz2.ini
    sed -i -e 's/extension=pdo_sqlite/;extension=pdo_sqlite/' /etc/php.d/30-pdo_sqlite.ini
    sed -i -e 's/extension=sqlite3/;extension=sqlite3/' /etc/php.d/20-sqlite3.ini
    sed -i -e 's/extension=wddx/;extension=wddx/' /etc/php.d/30-wddx.ini  
    
    mkdir -p /var/run/php/
    NEWKEY="listen = /var/run/php/php${PHP_P}.${PHP_S}-fpm.sock"
    line_change 'listen = ' ${FPMCONF} "${NEWKEY}"    
    NEWKEY="listen.owner = ${USER}"
    line_change 'listen.owner = ' ${FPMCONF} "${NEWKEY}"
    NEWKEY="listen.group = ${GROUP}"
    line_change 'listen.group = ' ${FPMCONF} "${NEWKEY}"
    NEWKEY='listen.mode = 0660'
    line_change 'listen.mode = ' ${FPMCONF} "${NEWKEY}"  
    NEWKEY='listen.backlog = 4096'
    line_change 'listen.backlog' ${FPMCONF} "${NEWKEY}"   
}    

ubuntu_setup_apache(){
    echoG 'Setting Apache Config'
    cd ${SCRIPTPATH}/
    a2enmod proxy_fcgi >/dev/null 2>&1
    a2enconf php${PHP_P}.${PHP_S}-fpm >/dev/null 2>&1
    a2enmod mpm_event >/dev/null 2>&1
    a2enmod ssl >/dev/null 2>&1
    a2enmod http2 >/dev/null 2>&1
    a2disconf other-vhosts-access-log >/dev/null 2>&1
    cp webservers/apache/conf/deflate.conf ${APADIR}/mods-available
    cp webservers/apache/conf/default-ssl.conf ${APADIR}/sites-available
    if [ ! -e ${APADIR}/sites-enabled/000-default-ssl.conf ]; then
        ln -s ${APADIR}/sites-available/default-ssl.conf ${APADIR}/sites-enabled/000-default-ssl.conf
    fi
    if [ ! -e ${APADIR}/conf-enabled/php${PHP_P}.${PHP_S}-fpm.conf ]; then 
        ln -s ${APADIR}/conf-available/php${PHP_P}.${PHP_S}-fpm.conf ${APADIR}/conf-enabled/php${PHP_P}.${PHP_S}-fpm.conf 
    fi
    sed -i "s/80/${APACHE_HTTP_PORT}/g" ${APADIR}/sites-available/000-default.conf
    sed -i "s/80/${APACHE_HTTP_PORT}/g" ${APADIR}/sites-enabled/000-default.conf
    sed -i "s/80/${APACHE_HTTP_PORT}/g" ${APADIR}/ports.conf
    sed -i "s/443/${APACHE_HTTPS_PORT}/g" ${APADIR}/sites-available/default-ssl.conf
    sed -i "s/443/${APACHE_HTTPS_PORT}/g" ${APADIR}/ports.conf
    sed -i '/ CustomLog/s/^/#/' ${APADIR}/sites-enabled/000-default.conf
    systemctl restart apache2
}

centos_setup_apache(){
    echoG 'Setting Apache Config'
    cd ${SCRIPTPATH}/
    echo "Protocols h2 http/1.1" >> /etc/httpd/conf/httpd.conf
    sed -i '/logs\/access_log" common/s/^/#/' /etc/httpd/conf/httpd.conf
    sed -i '/LoadModule mpm_prefork_module/s/^/#/g' /etc/httpd/conf.modules.d/00-mpm.conf
    sed -i '/LoadModule mpm_event_module/s/^#//g' /etc/httpd/conf.modules.d/00-mpm.conf
    sed -i "s+SetHandler application/x-httpd-php+SetHandler proxy:unix:/var/run/php/php${PHP_P}.${PHP_S}-fpm.sock|fcgi://localhost+g" \
        /etc/httpd/conf.d/php.conf
    cp webservers/apache/conf/deflate.conf ${APADIR}/conf.d
    cp webservers/apache/conf/default-ssl.conf ${APADIR}/conf.d
    sed -i '/ErrorLog/s/^/#/g' /etc/httpd/conf.d/default-ssl.conf
    sed -i "s/80/${APACHE_HTTP_PORT}/g" ${APADIR}/conf/httpd.conf
    sed -i "s/443/${APACHE_HTTPS_PORT}/g" ${APADIR}/conf.d/default-ssl.conf
    systemctl restart httpd
}

ubuntu_setup_ols(){
    echoG 'Setting OpenLiteSpeed Config'
    cd ${SCRIPTPATH}/
    backup_old ${OLSDIR}/conf/httpd_config.conf
    backup_old ${OLSDIR}/Example/conf/vhconf.conf
    cp ./webservers/openlitespeed/conf/httpd_config.conf ${OLSDIR}/conf/
    cp ./webservers/openlitespeed/conf/vhconf.conf ${OLSDIR}/conf/vhosts/Example/
    sed -i "s/\:80/\:${APACHE_HTTP_PORT}/g" ${OLSDIR}/conf/vhosts/Example/vhconf.conf
    sed -i "s/\:443/\:${APACHE_HTTPS_PORT}/g" ${OLSDIR}/conf/vhosts/Example/vhconf.conf
    change_owner ${OLSDIR}/cachedata
    service lsws restart
}

centos_setup_ols(){
    echoG 'Setting OpenLiteSpeed Config'
    cd ${SCRIPTPATH}/
    backup_old ${OLSDIR}/conf/httpd_config.conf
    backup_old ${OLSDIR}/Example/conf/vhconf.conf
    cp ./webservers/openlitespeed/conf/httpd_config.conf ${OLSDIR}/conf/
    cp ./webservers/openlitespeed/conf/vhconf.conf ${OLSDIR}/conf/vhosts/Example/
    sed -i "s/www-data/${USER}/g" ${OLSDIR}/conf/httpd_config.conf
    sed -i "s|/usr/local/lsws/lsphp${PHP_P}${PHP_S}/bin/lsphp|/usr/bin/lsphp|g" ${OLSDIR}/conf/httpd_config.conf
    sed -i "s/:80/:${APACHE_HTTP_PORT}/g" ${OLSDIR}/conf/vhosts/Example/vhconf.conf
    sed -i "s/:443/:${APACHE_HTTPS_PORT}/g" ${OLSDIR}/conf/vhosts/Example/vhconf.conf    
    change_owner ${OLSDIR}/cachedata
    service lsws restart
}

prepare(){
    check_os
    path_update
    gen_selfsigned_cert
}

cleanup(){
    rm -f /tmp/lshttpd/.rtreport
}

testcase(){
    curl -Iks --http1.1 http://127.0.0.1:80/ | grep -i LiteSpeed && echoG 'Good' || echoR 'Please check'
    curl -Iks --http1.1 https://127.0.0.1:443/ | grep -i LiteSpeed && echoG 'Good' || echoR 'Please check'
    curl -Iks --http1.1 http://127.0.0.1:${APACHE_HTTP_PORT}/ | grep -i Apache && echoG 'Good' || echoR 'Please check'
    curl -Iks --http1.1 https://127.0.0.1:${APACHE_HTTPS_PORT}/ | grep -i Apache && echoG 'Good' || echoR 'Please check'
}

main(){
    prepare
    if [ ${OSNAME} = 'centos' ]; then 
        centos_pkg_basic
        centos_install_apache
        centos_install_ols
        centos_install_php
        centos_setup_apache
        centos_setup_ols
    else
        ubuntu_pkg_basic
        ubuntu_install_apache
        ubuntu_install_ols
        ubuntu_install_php
        ubuntu_setup_apache
        ubuntu_setup_ols
    fi
    cleanup
    testcase
}
main