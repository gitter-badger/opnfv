# Foreman install for opensteak

Installation for Ubuntu 14.04

## Install foreman

### Prepare repos

```
echo "deb http://deb.theforeman.org/ trusty 1.7" > /etc/apt/sources.list.d/foreman.list
echo "deb http://deb.theforeman.org/ plugins 1.7" >> /etc/apt/sources.list.d/foreman.list
wget -q http://deb.theforeman.org/pubkey.gpg -O- | apt-key add -
apt-get update && apt-get install foreman-installer

```

### Install Foreman

```
gem install rubyipmi
sudo foreman-installer \
 --enable-foreman-proxy\
 --enable-foreman-plugin-templates\
 --enable-foreman-plugin-discovery\
 --foreman-plugin-discovery-install-images=true\
 --enable-foreman-compute-libvirt\
 --foreman-proxy-bmc=true\
 --foreman-proxy-tftp=true\
 --foreman-proxy-tftp-servername=192.168.1.4\
 --foreman-proxy-dhcp=true\
 --foreman-proxy-dhcp-interface=eth0\
 --foreman-proxy-dhcp-gateway=192.168.1.4\
 --foreman-proxy-dhcp-range="192.168.1.10 192.168.1.150"\
 --foreman-proxy-dhcp-nameservers="192.168.1.4"\
 --foreman-proxy-dns=true\
 --foreman-proxy-dns-interface=eth0\
 --foreman-proxy-dns-zone=infra.opensteak.fr\
 --foreman-proxy-dns-reverse=1.168.192.in-addr.arpa\
 --foreman-proxy-dns-forwarders=8.8.8.8\
 --foreman-proxy-foreman-base-url=https://localhost

### Sync community templates for last ubuntu versions
```
foreman-rake templates:sync
```

### Set AppArmor

```
perl -i -pe 's!#include <local/usr.sbin.dhcpd>!include <local/usr.sbin.dhcpd>!' /etc/apparmor.d/usr.sbin.dhcpd
echo "/etc/bind/rndc.key r," >> /etc/apparmor.d/local/usr.sbin.dhcpd
service apparmor reload
```

### Gen SSH key for foreman

```
su foreman -s /bin/bash
ssh-keygen
exit
```

### Set templates

```
Template: PXELinux global default template
LABEL discovery
MENU LABEL Foreman Discovery
MENU DEFAULT
KERNEL boot/fdi-image/vmlinuz0
APPEND initrd=boot/fdi-image/initrd0.img rootflags=loop root=live:/fdi.iso rootfstype=auto ro rd.live.image acpi=force rd.luks=0 rd.md=0 rd.dm=0 rd.lvm=0 rd.bootif=0 rd.neednet=0 nomodeset proxy.url=http://192.168.1.4 proxy.type=foreman
IPAPPEND 2
Template: provision
Modifier la dernière ligne pour avoir :
d-i preseed/late_command string wget -Y off <%= @static ? "'#{foreman_url('finish')}&static=true'" : foreman_url('finish') %> -O /target/tmp/finish.sh && in-target chmod +x /tmp/finish.sh && in-target /tmp/finish.sh && rm -f /usr/lib/finish-install.d/55netcfg-copy-config
(ajout du  rm -f /usr/lib/finish-install.d/55netcfg-copy-config)
vu sur : http://projects.theforeman.org/projects/foreman/wiki/Tips_&amp_Tricks#Generating-etcnetworkinterfaces
#Creation user
# The user's name and login.
d-i passwd/make-user boolean true
user-setup-udeb passwd/make-user boolean true
passwd passwd/user-fullname string ubuntu
passwd passwd/username string ubuntu
d-i passwd/user-password-crypted password <%= root_pass %>
d-i passwd/user-default-groups string ubuntu adm dialout cdrom floppy sudo audio dip video plugdev netdev
```

```
# Modification de la conf de base
Dans les parametres
- passer la variable ignore_puppet_facts_for_provisioning à true (vu sur http://projects.theforeman.org/issues/1861#note-2)
- passer la varable safemode_render à false

```

### Check boot image

If there is no boot image:
```
ls /var/lib/tftpboot/boot/
```

```
wget http://downloads.theforeman.org/discovery/releases/latest/fdi-image-latest.tar \
  -O - | tar x --overwrite -C /var/lib/tftpboot/boot
```

## Install opensteak classes

TO BE COMPLETED

## Apply puppet classes to foreman

### Set DHCP server
Apply puppet class ''opensteak::dhcp'' to foreman:

Set those parameter in foreman GUI for foreman server

```
  opensteak::dhcp:
    dnsdomain:
    - infra.opensteak.fr
    - storage.infra.opensteak.fr
    - vm.infra.opensteak.fr
    - 0.168.192.in-addr.arpa
    - 1.168.192.in-addr.arpa
    - 2.168.192.in-addr.arpa
    interfaces:
    - eth0
    - eth1
    - eth2
    pools:
      pools:
        infra.opensteak.fr:
          network: 192.168.1.0
          netmask: 255.255.255.0
          range: 192.168.1.20 192.168.1.170
          gateway: 192.168.1.1
        storage.infra.opensteak.fr:
          network: 192.168.0.0
          netmask: 255.255.255.0
          range: 192.168.0.20 192.168.0.170
        vm.infra.opensteak.fr:
          network: 192.168.2.0
          netmask: 255.255.255.0
          range: 192.168.2.20 192.168.2.170
```

### Prepare Bind server

TO BE COMPLETED

### Run puppet

Run puppet on foreman