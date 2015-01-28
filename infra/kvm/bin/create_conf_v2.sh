#!/bin/bash

# Script name
PRGNAME=$(basename $0)

# Root folder
ROOT='/usr/local/opensteak/infra'

#################################################
# Fonction to load hiera data
#################################################
function hiera_get {
    hiera -c $ROOT/hiera.yaml "$1"
    return $?
}
function hiera_get_hash_value {
    hiera_get "$1" |grep "\"$2\"" |perl -pe "s/.*\"$2\"=>\"(.*?)\".*/\1/g"
    return $?
}

#################################################
# Usage
#################################################
function usage() {

    cat << EOF >&1
Usage: $PRGNAME [options] MACHINENAME

Description: This script will create config files for a VM in 
             current folder

Options:
    --help, -h
        Print this help and exit.

    --name, -n NAME
        Set the name of tthe machine

    --ip, -i XXX.XXX.XXX
        Set the ip address of the machine.

    --password, -p PASSWORD
        Set the ssh password. Login is ubuntu.

    --targetpool, -t POOL
        Set the target pool to install the volume

    --cloud-init, -x CLOUDINITTEMPLATE
        Set the cloud init file template

    --meta-data, -y METADATATEMPLATE
        Set the meta-data file template

    --kvm-config, -k KVMCONFIGTEMPLATE
        Set the KVM config file template

    --cpu, -l NUMBEROFCPU
        Set number of CPU for the VM
        
    --mem, -m MEMQUANTITY
        Set quantity of RAM for the VM

    --createvm, -c
        Automatically create the VM after the configuration
        is done.
        
    --storage, -s
        Add a network interface based on YAML config files
        
EOF
    echo -n '0'
    exit 0
}

#################################################
# Get Args
#################################################

# Command line argument parsing, the allowed arguments are
# alphabetically listed, keep it this way please.
LOPT="help,name:,ip:,password:,cloud-init:,meta-data:,kvm-config:,cpu:,mem:,targetpool:,createvm,storage"
SOPT="hn:i:p:x:y:k:l:m:t:cs"

# Note that we use `"$@"' to let each command-line parameter expand to a
# separate word. The quotes around `$@' are essential!
# We need TEMP as the `eval set --' would nuke the return value of getopt.
TEMP=$(getopt --options=$SOPT --long $LOPT -n $PRGNAME -- "$@")

if [[ $? -ne 0 ]]; then
    echo "Error while parsing command line args. Exiting..." >&2
    exit 1
fi
# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true; do
  case $1 in
    --help|-h)
                        usage
                        exit 0
                        ;;
    --name|-n)
                        NAME=$2; shift
                        ;;
    --ip|-i)
                        IP=$2; shift
                        ;;
    --targetpool|-t)
                        TARGETPOOL=$2; shift
                        ;;
    --password|-p)
                        PASSWORD=$2; shift
                        ;;
    --cloud-init|-x)
                        CLOUDINITTEMPLATE=$2; shift
                        ;;
    --meta-data|-y)
                        METADATATEMPLATE=$2; shift
                        ;;
    --kvm-config|-k)
                        KVMCONFIGTEMPLATE=$2; shift
                        ;;
    --cpu|-l)
                        CPU=$2; shift
                        ;;
    --ram|-m)
                        RAM=$2; shift
                        ;;
    --createvm|-c)
                        CREATEVM="y"
                        ;;
    --storage|-s)
                        NETSTORAGE="y"
                        ;;
    --)
                        shift
                        break
                        ;;
    *)
                        echo "Unknow argument \"$1\"" >&2
                        exit 1
                        ;;
  esac
  shift
done

#################################################
# Check args
#################################################

# check name
if [ -z "$NAME" ]; then
    echo "Please provide a valid machine name. See --help option."  >&2
    exit 1
fi

# if no IP fetch default one in the config
if [ -z "$IP" ]; then
    if [ "$NAME" = 'dns' ] || [ "$NAME" = 'puppet' ]; then
        IP=$(hiera_get_hash_value infra::vm $NAME)
    else
        IP=$(hiera_get_hash_value stack::vm $NAME)
    fi
    IP_NET=$(hiera_get infra::network)
    IP_MASK=$(hiera_get infra::network_mask)
    IP_BC=$(hiera_get infra::network_broadcast)
    IP_GW=$(hiera_get infra::network_gw)
    IP_EXT_DNS=$(echo $(hiera_get dns::external)| perl -pe 's/[\[\],\"]//g')
    IP_INT_DNS=$(hiera_get infra::dns) 
    IP_DNS="$IP_INT_DNS $IP_EXT_DNS"
    IP_DNSSEARCH=$(hiera_get stack::domain)
fi
# If not target pool use ceph if available
CEPH_POOL_NAME=$(hiera_get ceph::pool)
DEFAULT_POOL_NAME=$(hiera_get kvm::default::pool::name)
if [ -z "$TARGETPOOL" ]; then
    if virsh pool-list | grep " $CEPH_POOL_NAME " > /dev/null; then
        TARGETPOOL=$CEPH_POOL_NAME
        TARGETFOLDER=$(hiera_get ceph::mount)
    else
        TARGETPOOL=$DEFAULT_POOL_NAME
        TARGETFOLDER=$(hiera_get kvm::default::pool::mount)
    fi
else
    if [ "$TARGETPOOL" = $CEPH_POOL_NAME ] && virsh pool-list | grep " $CEPH_POOL_NAME " > /dev/null; then
        TARGETFOLDER=$(hiera_get ceph::mount)
    elif [ "$TARGETPOOL" = "default" ] && virsh pool-list | grep " default " > /dev/null; then
        TARGETFOLDER=$(hiera_get kvm::default::pool::mount)
    else
        echo "Please provide a valid target pool. Available pools are listed in 'virsh pool-list'"  >&2
        exit 1
    fi
fi

# Check or get cloud-init file
if [ -z "$CLOUDINITTEMPLATE" ]; then
    CLOUDINITTEMPLATE=$(hiera_get kvm::default::init)
fi

# Check or get cloud-init file
if [ -z "$KVMCONFIGTEMPLATE" ]; then
    if [ "Zy" = "Z$NETSTORAGE" ]; then
        KVMCONFIGTEMPLATE=$(hiera_get kvm::default::conf_storage)
    else
        KVMCONFIGTEMPLATE=$(hiera_get kvm::default::conf)
    fi
fi

# Check or get  meta-data file
if [ -z "$METADATATEMPLATE" ]; then
    if [ "Zy" = "Z$NETSTORAGE" ]; then
        METADATATEMPLATE=$(hiera_get kvm::default::net_storage)
    else
        METADATATEMPLATE=$(hiera_get kvm::default::net)
    fi
fi

# Check CPU
if [ -z "$CPU" ]; then
    CPU=$(hiera_get kvm::default::cpu)
fi

# Check RAM
if [ -z "$RAM" ]; then
    RAM=$(hiera_get kvm::default::ram)
fi

# check password
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(hiera_get kvm::password)
fi

# If we need an interface on storage network, get data
if [ "Zy" = "Z$NETSTORAGE" ]; then
    IP_S=$(hiera_get_hash_value stack::vm $NAME-storage)
    if [ "$IP_S" = "nil" ]; then
        echo "Can not get storage IP for the VM. See --help option and config files."  >&2
        exit 1
    fi
    IP_S_NET=$(hiera_get storage::network)
    IP_S_MASK=$(hiera_get storage::network_mask)
    IP_S_BC=$(hiera_get storage::network_broadcast)
fi

#################################################
# Ask confirmation
#################################################

RESUME="
 - name: $NAME
 - user ubuntu with password: '$PASSWORD'
 - pool: '$TARGETPOOL'
 - pool folder: '$TARGETFOLDER'
 - config file: '$KVMCONFIGTEMPLATE'
 - cloud init file: '$CLOUDINITTEMPLATE'
 - cloud meta-data: '$METADATATEMPLATE'
 - cpu: $CPU
 - ram: $RAM 
 - Network:
    - IP: '$IP'
    - Network : '$IP_NET'
    - Broadcast : '$IP_BC'
    - Mask : '$IP_MASK'
    - Gateway : '$IP_GW'
    - DNS: '$IP_DNS'
    - DNS search: '$IP_DNSSEARCH'"
if [ "Zy" = "Z$NETSTORAGE" ]; then
    RESUME="$RESUME
 - Storage Network:
    - IP: '$IP_S'
    - Network : '$IP_S_NET'
    - Broadcast : '$IP_S_BC'
    - Mask : '$IP_S_MASK'"
fi

echo "Creating VM configuration in folder '$ROOT/kvm/vm_configs/$NAME' with
$RESUME
 "
if [ "Zy" = "Z$CREATEVM" ]; then
    echo "Will also create the VM."
fi
echo 
read -p "------ PRESS ANY KEY TO CONTINUE -------" -n 1 -r
echo
echo

mkdir -p "$ROOT/kvm/vm_configs/$NAME"
cd "$ROOT/kvm/vm_configs/$NAME"

#################################################
# Save config for log
#################################################

echo "$RESUME" > config.log

#################################################
# Set Metadata file
#################################################

cp "$ROOT/$METADATATEMPLATE" meta-data
perl -i -pe "s/__PASSWORD__/$PASSWORD/" meta-data
perl -i -pe "s/__IP__/$IP/" meta-data
perl -i -pe "s/__NETWORK__/$IP_NET/" meta-data
perl -i -pe "s/__MASK__/$IP_MASK/" meta-data
perl -i -pe "s/__BC__/$IP_BC/" meta-data
perl -i -pe "s/__GW__/$IP_GW/" meta-data
perl -i -pe "s/__DNS__/$IP_DNS/" meta-data
perl -i -pe "s/__DNSSEARCH__/$IP_DNSSEARCH/" meta-data
perl -i -pe "s/__NAME__/$NAME/" meta-data
if [ "Zy" = "Z$NETSTORAGE" ]; then
    perl -i -pe "s/__IP_S__/$IP_S/" meta-data
    perl -i -pe "s/__NETWORK_S__/$IP_S_NET/" meta-data
    perl -i -pe "s/__MASK_S__/$IP_S_MASK/" meta-data
    perl -i -pe "s/__BC_S__/$IP_S_BC/" meta-data
fi

#################################################
# Set cloud-init
#################################################

cp "$ROOT/$CLOUDINITTEMPLATE" user-data
perl -i -pe "s/__PASSWORD__/$PASSWORD/" user-data
perl -i -pe "s/__NAME__/$NAME/" user-data

#################################################
# Generate ISO
#################################################
genisoimage -output $NAME-configuration.iso -volid cidata -joliet -rock user-data meta-data
sudo mv $NAME-configuration.iso $TARGETFOLDER/
virsh pool-refresh $TARGETPOOL 2>/dev/null

#################################################
# Generate Config file
#################################################

cp "$ROOT/$KVMCONFIGTEMPLATE" $NAME.xml
perl -i -pe "s/__CPU__/$CPU/" $NAME.xml
perl -i -pe "s/__MEM__/$MEM/" $NAME.xml
perl -i -pe "s!__TARGETFOLDER__!$TARGETFOLDER!" $NAME.xml
perl -i -pe "s/__NAME__/$NAME/" $NAME.xml

#################################################
# Generate Config file
#################################################
exit 
# Create the VM
if [ "Zy" = "Z$CREATEVM" ]; then
    export NAME="$NAME"
    export TARGETPOOL="$TARGETPOOL"
    create_vm.sh
fi
