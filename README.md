# Running sshd from initrd

# Why?
There might be additional use cases but the most obvious one is so that you can provide a password to decrypt your filesystem without having physical (or other form of virtual console) access to the machine.

# Credits
Credit where credit is due - we rely heavily on https://github.com/gsauthof/dracut-sshd/tree/master by Georg Sauthoff.
In fact this is mostly a reuse of that project, just automating it a bit and making an RH-derivative specific.

# Prerequisites
* A compatible distro (other distros might work but might need some adjustments - for example, EPEL will surely not work with debian, Slackware or Gentoo) Linux. This procedure was tested on Alma Linux 9 but should also work on 8, possibly on earlier ones as well
* Public ssh key for authentication
* All commands provided below must be run as root or with sudo

# TL;DR
* download the `prepare_initrd.sh` file
* edit the variables at the beginning
* run it
* profit

# The long way with explanation

## EPEL needed
Since we require systemd-networkd during boot we need to enable EPEL distro which provides it.
```
dnf install epel-repo
```

## Install and configure systemd-networkd
```
dnf install systemd-networkd
```

We shouldn't need to adjust the default `networkd.conf` but we need to create a connection description in `/etc/systemd/network`. Create a file with `.network` extension describing your network connection. If you have a static DHCP lease you might use DHCP, we'll use static addressing.
The `Name` option must of course match your interface name and the `DNS` option probably doesn't matter here. My example:
```
[Match]
Name=enp1s0

[Network]
Address=192.168.122.111/24
Gateway=192.168.122.1
DNS=192.168.122.1
```
The `Name` must match your interface name obviously.
For more options see `man systemd.network`

## Disable systemd-networkd
This is a rather unintuitive step. By default our system uses NetworkManager and we don't mind that. But since we want systemd-networkd to run during initrd phase we need to stop the systemd-networkd immediately when it stops being needed so it doesn't interfere with normal NetworkManager operations.
```
systemctl disable systemd-networkd
```

## Disable the interface
This is a yet more unintuitive step. Without it NetworkManager can get confused about the state of the interfaces after boot. We need to make sure the interface we configured during initrd stage is down so that NM can handle it properly.

For that we create a service file in `/etc/systemd/system` let's calle it `disable-boot-interface.service`. Its contents:
```
[Unit]
Description=Disable interface configured on boot
DefaultDependencies=no
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=-/usr/bin/nmcli c down enp1s0

[Install]
WantedBy=network-online.target
```
Again - the interface name must match your system so tweak it accordingly.

## Configure dracut

There are two parts to it.
Firstly, you have to get the `46sshd` directory from https://github.com/gsauthof/dracut-sshd/tree/master into your /usr/lib/dracut/modules.d
Do it whatever way you want - git, wget, curl. Just get those files there.

Then you need to make sure your modules are included in your initrd. For this you have to create a config file in `/etc/dracut.conf.d` with filename ending with `.conf` including the network modules. Example contents are in the original project - https://github.com/gsauthof/dracut-sshd/blob/master/example/90-networkd.conf

## Add your own ssh keys

Of course you need to be able to log into the box. So make `/etc/dracut-sshd/authorized-keys` with your trusted ssh keys which you will use to ssh to this box.

## Rebuild initrds

And finally, when everything is in place, just rebuild existing initrds so that they include your new components.
For example:
```
dracut -f --kver 5.14.0-503.16.1.el9_5.x86_64 /boot/initramfs-5.14.0-503.16.1.el9_5.x86_65
```

You can also batch-recreate (almost) all initrds on your system:
```
cd /boot
find . -type f -name vmlinuz-\* | grep -v rescue | while read VMLINUZ; do
    VER=${VMLINUZ#./vmlinuz-}
    INITRAMFS=initramfs-$VER.img
    echo Found kernel: $VMLINUZ
    echo Version: $VER
    echo Needs initramfs: $INITRAMFS
    dracut -f --kver $VER $INITRAMFS
    echo
done
```

## Reboot and test
And that's it.
Typical problems:
* wrong interface specified
* wrong address configured
* initrd not rebuild (check contents with lsinitrd)
