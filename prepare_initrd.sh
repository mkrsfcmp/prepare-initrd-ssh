#!/usr/bin/env bash

# Configuration goes here
IPADDR=192.168.122.111/24
IPGW=192.168.122.1
IFACE=enp1s0
NETWORK_NAME=20-wired
SSHKEYS="here go your
authorized
ssh keys
"

# It makes no sense to try this all without proper privileges
if [ $UID -ne 0 ]; then
    echo "Come on, run me as root. Don't be a wimp!"
    exit 1
fi

# Safeguard
if [ "$1" != "-f" ]; then
  cat << __EOF__
Warning! Pieces of configuration will be automatically created and possibly overwritten.
Target configuration:
Interface:  $IFACE
IP Address: $IPADDR
Gateway:    $IPGW
Ssh keys:
$SSHKEYS

If this is not what you want, press Ctrl-C now!
Otherwise press enter to continue.
__EOF__
  read
fi

# We bail out in case of any trouble
set -e

# systemd-networkd is in EPEL so we need it enabled
dnf install -y epel-release

# Install the package
dnf install -y systemd-networkd

# But disable the service (we need it only at the initrd level; later it will
# interfere with NetworkManager)
systemctl disable systemd-networkd

# Create network description file
FILE=/etc/systemd/network/"$NETWORK_NAME".network
cat > "$FILE" <<_EOF_
[Match]
Name=$IFACE

[Network]
Address=$IPADDR
Gateway=$IPGW
_EOF_

# After booting we need to disable the interface we configured during initrd stage

cat > /etc/systemd/system/disable-boot-interface.service << __EOF__
[Unit]
Description=Disable interface configured on boot
DefaultDependencies=no
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=-/usr/bin/nmcli c down $IFACE

[Install]
WantedBy=network-online.target
__EOF__

# We could clone it with git but this way we don't need additional tools.

install -d /usr/lib/dracut/modules.d/46sshd
pushd /usr/lib/dracut/modules.d/46sshd
for FILE in module-setup.sh motd profile sshd.service sshd_config; do
   curl https://raw.githubusercontent.com/gsauthof/dracut-sshd/refs/heads/master/46sshd/"$FILE" -o "$FILE"
done
popd

# Now that we have the module for ssh and systemd-networkd we need to add them
# to our dracut configuration

FILE=/etc/dracut.conf.d/90-networkd.conf
cat > "$FILE" << _EOF_
install_items+=" /etc/systemd/network/$NETWORK_NAME.network "
add_dracutmodules+=" systemd-networkd "
_EOF_

# And we need to create known keys for the initrd sshd
install -d /etc/dracut-sshd
echo "$SSHKEYS" > /etc/dracut-sshd/authorized_keys

# And for the final step - recreate our initrds (ignore the rescue one)

cd /boot
find . -type f -name vmlinuz-\* | grep -v rescue | while read VMLINUZ; do
    VER=${VMLINUZ#./vmlinuz-}
    INITRAMFS=initramfs-$VER.img
    echo Found kernel: $VMLINUZ
    echo Version: $VER
    echo Needs initramfs: $INITRAMFS
    dracut -f --kver $VER $INITRAMFS
    echo done
    echo
done

echo Finished. You can reboot now.
