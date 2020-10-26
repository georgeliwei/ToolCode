#!/bin/bash

TFTP_CFG="tftpd-hpa"
ISC_CFG="isc-dhcp-server"
DHCP_CFG="dhcpd.conf"
HTTP_CFG="000-default.conf"
PXE_CFG="default"
ATUO_INSTALL_CFG=""


function install_tftp_service()
{
    yes | apt-get install tftpd-hpa
}

function install_dhcp_service()
{
    yes | apt-get install isc-dhcp-server
}

function install_http_service()
{
    yes | apt-get install apache2
}

function check_service_status()
{
    service_name=$1
    sercice_status=`systemctl status ${service_name} | grep Active | awk '{print $3}' | awk -F '[()]' '{print $2}'`
    if [ "${sercice_status}" != "running" ];then
        echo "${service_name} is not runnint, please check!!!"
        exit 1
    fi
}

function create_tftp_config()
{
    tftpdir=$1
    tftpcfgname=$TFTP_CFG
    echo "TFTP_USERNAME=\"tftp\"
TFTP_DIRECTORY=\"${tftpdir}\"
TFTP_ADDRESS=\":69\"
TFTP_OPTIONS=\"--secure\"
" > $tftpcfgname
}

function create_dhcp_config()
{
    netInterface=$1
    pxe_server_ip=$2
    dhcpServerCfgFile=$ISC_CFG
    dhcpOptionCfgFile=$DHCP_CFG

    OLD_IFS="$IFS"
    IFS="."
    ipSplit=($pxe_server_ip)
    IFS="$OLD_IFS"
    ip_range_start=${ipSplit[0]}.${ipSplit[1]}.${ipSplit[2]}.10
    ip_range_end=${ipSplit[0]}.${ipSplit[1]}.${ipSplit[2]}.20
    ip_bcast=${ipSplit[0]}.${ipSplit[1]}.${ipSplit[2]}.255
    netInterfaceIpSeg=${ipSplit[0]}.${ipSplit[1]}.${ipSplit[2]}.0
    netInterfaceMask=255.255.255.0

    echo "INTERFACESv4=\"${netInterface}\"
INTERFACESv6=\"${netInterface}\"
" > $dhcpServerCfgFile

    echo "option domain-name \"autopxe.com\";
option domain-name-servers srv.autopxe.com;
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;
subnet ${netInterfaceIpSeg} netmask ${netInterfaceMask} {
    range ${ip_range_start} ${ip_range_end};
    option routers $pxe_server_ip;
    option subnet-mask ${netInterfaceMask};
    option domain-name-servers $pxe_server_ip;
    option ntp-servers $pxe_server_ip;
    option netbios-name-servers $pxe_server_ip;
    option broadcast-address ${ip_bcast};
    next-server $pxe_server_ip;
    filename \"pxelinux.0\";
    allow booting;
    allow bootp;
}" > $dhcpOptionCfgFile
}

function set_dhcp_netinterface_ip()
{
    interface=$1
    ip=$2
    mask=$3
    ip addr add $ip/$mask dev $interface
}

function create_http_config()
{
    http_root_dir=$1
    http_cfg=$HTTP_CFG
    echo "
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot ${http_root_dir}
    <Directory "${http_root_dir}">
        Options Indexes
        AllowOverride All
        Allow from all
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
" > $http_cfg
}

function prepare_tftp_env()
{

    tftpRootDir=$1
    curdir=$PWD
    mkdir -p $tftpRootDir
    tftp_full_path=$curdir/${tftpRootDir}
    create_tftp_config $tftp_full_path
    install_tftp_service
    cp -rf $TFTP_CFG /etc/default/
}
function prepare_dhcp_env()
{
    nic=$1
    pxe_ip=$2
    install_dhcp_service
    create_dhcp_config $nic $pxe_ip
    cp -rf $ISC_CFG /etc/default/
    cp -rf $DHCP_CFG /etc/dhcp/
}
function prepare_http_env()
{
    iso_img=$1
    http_root_dir=$2
    mkdir -p $http_root_dir
    cur_dir=$PWD
    http_full_root_dir=$cur_dir/$http_root_dir
    cp -rf $iso_img $http_root_dir
    install_http_service
    create_http_config $http_full_root_dir
    cp -rf $HTTP_CFG /etc/apache2/sites-available/
}

function create_pxe_ubuntu204_default_cfg()
{
    default_name="default"
    http_server=$1
    iso_name=$2
    echo "DEFAULT install
LABEL install
    KERNEL vmlinuz
    INITRD initrd
    APPEND root=/dev/ram0 ramdisk_size=1500000 ip=dhcp url=http://$http_server/$iso_name autoinstall ds=nocloud-net;s=http://$http_server/
" > $default_name
}
function prepare_ubuntu_204_pxe_file()
{
    isoimg=$1
    tftpdir=$2
    pxe_ip=$3
    curdir=$PWD
    mkdir -p tmp
    mount -t iso9660 $isoimg ./tmp
    cp ./tmp/casper/initrd $tftpdir/
    cp ./tmp/casper/vmlinuz $tftpdir/
    cp ./tmp/isolinux/ldlinux.c32 $tftpdir/
    cp -rf pxelinux.0 $tftpdir/
    mkdir -p $tftpdir/pxelinux.cfg/
    create_pxe_ubuntu204_default_cfg $pxe_ip $isoimg
    umount ./tmp
    rm -rf tmp
}
function prepare_ubuntu_204_auto_install_cfg()
{
    cat > user-data << 'EOF'
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ubuntu-server
    password: "$6$exDY1mhS4KUYCE/2$zmn9ToZwTKLhCw.b4/b.ZRTIZM30JZ4QrOQ2aOXJ8yk96xpcCof0kxKwuX1kqLG/ygbJ1f8wxED22bTL4F46P0"
    username: ubuntu
EOF
    touch meta-data
}
function prepare_pxe_env()
{
    iso=$1
    tftpdir=$2
    pxeip=$3
    prepare_ubuntu_204_pxe_file $iso $tftpdir $pxeip
    cp -f $PXE_CFG $tftpdir/pxelinux.cfg/
}
function prepare_auto_install_env()
{
    httpdir=$1
    prepare_ubuntu_204_auto_install_cfg
    cp -rf user-data $httpdir
    cp -rf meta-data $httpdir
}

function check_all_service()
{
    systemctl restart tftpd-hpa
    systemctl restart apache2
    systemctl restart isc-dhcp-server
    check_service_status tftpd-hpa
    check_service_status apache2
    check_service_status isc-dhcp-server
    echo "==============================="
    echo "==="
    echo "===   All service OK"
    echo "==="
    echo "==============================="
}

function main()
{
    iso_img=$1
    nic=$2
    pxe_ip="192.168.1.1"
    pxe_mask_len="24"
    tftp_root_dir="TftpDir"
    http_root_dir="HttpDir"
    #config pxe ip addr for nic interface
    set_dhcp_netinterface_ip $nic $pxe_ip $pxe_mask_len
    #prepare tftp env
    prepare_tftp_env $tftp_root_dir
    #prepare dhcp env
    prepare_dhcp_env $nic $pxe_ip
    #prepare http env
    prepare_http_env $iso_img $http_root_dir
    #prepare pxe env
    prepare_pxe_env $iso_img $tftp_root_dir $pxe_ip
    #prepare auto install config file
    prepare_auto_install_env $http_root_dir
    check_all_service
}

main $1 $2
