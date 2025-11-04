#!/usr/bin/env bash
set -e

BRANCH=${1:-dev}
read -p "Enter your rig's new hostname (this will be your rig's \"name\" in the future, so make sure to write it down): " -r
myrighostname=$REPLY

# Set hostname using hostnamectl if available (modern systemd systems), otherwise edit /etc/hostname directly
if command -v hostnamectl &> /dev/null; then
    hostnamectl set-hostname "$myrighostname"
else
    echo "$myrighostname" > /etc/hostname
fi

# Update /etc/hosts
sed -i "s/localhost\( jubilinux\)\?$/localhost $myrighostname/" /etc/hosts
sed -i "s/127\.0\.1\.1.*$/127.0.1.1       $myrighostname/" /etc/hosts

# if passwords are old, force them to be changed at next login
passwd -S root 2>/dev/null | grep 20[01][0-6] && passwd -e root
# automatically expire edison account if its password is not changed in 3 days
passwd -S edison 2>/dev/null | grep 20[01][0-6] && passwd -e edison -i 3

# Password checking for Raspbian/Raspberry Pi OS
if test -f /etc/os-release && grep -q -E 'Raspbian|Raspberry Pi' /etc/os-release ; then
    # Check if pi user exists and has default password
    if id -u pi &>/dev/null; then
        # Try to detect if password is still default by checking if it was never changed
        # or if user-setup-apply service indicates default password
        if test -f /run/sshwarn || passwd -S pi 2>/dev/null | grep -q '^pi P 01/01/1970\|^pi NP'; then
            echo "WARNING: Default password detected for 'pi' user!"
            echo "Please select a secure password for ssh logins to your rig:"
            echo 'For the "pi" account: (same password for multiple accounts is fine)'
            passwd pi
            passwdPrompt=1
        fi
    fi

    # Check root password if it exists and is enabled
    if passwd -S root 2>/dev/null | grep -q '^root P'; then
        # If root has a password set, check if it's old or default
        if passwd -S root 2>/dev/null | grep -q '^root P 01/01/1970'; then
            test ${passwdPrompt:-0} -ne 1 &&
                echo "Please select a secure password for ssh logins to your rig:"
            echo 'For the "root" account: (same password for multiple accounts is fine)'
            passwd root
        fi
    fi
    unset passwdPrompt
fi

# set timezone
dpkg-reconfigure tzdata

# Workaround for Jubilinux v0.2.0 (Debian Jessie) migration to LTS
if cat /etc/os-release | grep 'PRETTY_NAME="Debian GNU/Linux 8 (jessie)"' &> /dev/null; then
    # Disable valid-until check for archived Debian repos (expired certs)
    echo "Acquire::Check-Valid-Until false;" | tee -a /etc/apt/apt.conf.d/10-nocheckvalid
    # Replace apt sources.list with archive.debian.org locations
    echo -e "deb http://security.debian.org/ jessie/updates main\n#deb-src http://security.debian.org/ jessie/updates main\n\ndeb http://archive.debian.org/debian/ jessie-backports main\n#deb-src http://archive.debian.org/debian/ jessie-backports main\n\ndeb http://archive.debian.org/debian/ jessie main contrib non-free\n#deb-src http://archive.debian.org/debian/ jessie main contrib non-free" > /etc/apt/sources.list
    echo "Please consider upgrading your rig to Jubilinux 0.3.0 (Debian Stretch)!"
    echo "Jubilinux 0.2.0, based on Debian Jessie, is no longer receiving security or software updates!"
fi

# TODO: remove the `-o Acquire::ForceIPv4=true` once Debian's mirrors work reliably over IPv6
apt-get -o Acquire::ForceIPv4=true update && apt-get -o Acquire::ForceIPv4=true -y dist-upgrade && apt-get -o Acquire::ForceIPv4=true -y autoremove
apt-get -o Acquire::ForceIPv4=true update && apt-get -o Acquire::ForceIPv4=true install -y sudo strace tcpdump screen acpid vim locate ntpdate ntp
#check if edison user exists before trying to add it to groups

grep "PermitRootLogin yes" /etc/ssh/sshd_config || echo "PermitRootLogin yes" >>/etc/ssh/sshd_config

if  getent passwd edison > /dev/null; then
  echo "Adding edison to sudo users"
  adduser edison sudo
  echo "Adding edison to dialout users"
  adduser edison dialout
 # else
  # echo "User edison does not exist. Apparently, you are runnning a non-edison setup."
fi

sed -i "s/daily/hourly/g" /etc/logrotate.conf
sed -i "s/#compress/compress/g" /etc/logrotate.conf

curl -s https://raw.githubusercontent.com/lukaszarczynski/oref0/$BRANCH/bin/openaps-packages.sh | bash -
mkdir -p ~/src; cd ~/src && ls -d oref0 && (cd oref0 && git checkout $BRANCH && git pull) || git clone https://github.com/lukaszarczynski/oref0.git -b $BRANCH
echo "Press Enter to run oref0-setup with the current release ($BRANCH branch) of oref0,"
read -p "or press ctrl-c to cancel. " -r
cd && ~/src/oref0/bin/oref0-setup.sh
