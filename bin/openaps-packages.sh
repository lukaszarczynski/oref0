#!/usr/bin/env bash

die() {
    echo "$@"
    exit 1
}

# TODO: remove the `Acquire::ForceIPv4=true` once Debian's mirrors work reliably over IPv6
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4

apt-get install -y sudo
sudo apt-get update && sudo apt-get -y upgrade
## Modern distributions (Debian Bullseye+, Ubuntu 22.04+) use Python 3 by default and do not support python2 packages.
## Check if python2 packages are available (older systems like Debian Stretch/Buster)
if apt-cache show python 2>/dev/null | grep -q "Package: python" && apt-cache show python-pip 2>/dev/null | grep -q "Package: python-pip"; then
   # Old system with Python 2 packages still available
   sudo apt-get install -y git python python-dev software-properties-common python-numpy python-pip watchdog strace tcpdump screen acpid vim locate lm-sensors || die "Couldn't install packages"
else
   # Modern system (Bullseye+) - use Python 3 packages or Python 2 compatibility packages
   # Try python-is-python2 first (Bullseye), fall back to python-is-python3 (Bookworm+)
   if apt-cache show python-is-python2 2>/dev/null | grep -q "Package: python-is-python2"; then
      # Bullseye or similar - has python2 compatibility
      sudo apt-get install -y git python-is-python2 python-dev-is-python2 software-properties-common watchdog strace tcpdump screen acpid vim locate lm-sensors || die "Couldn't install packages"
      curl https://bootstrap.pypa.io/pip/2.7/get-pip.py | python2 || die "Couldn't install pip"
      python2 -m pip install numpy || die "Couldn't pip install numpy"
   else
      # Bookworm+ or modern Ubuntu - use Python 3 packages
      sudo apt-get install -y git python-is-python3 python3-dev software-properties-common python3-numpy python3-pip watchdog strace tcpdump screen acpid vim locate lm-sensors || die "Couldn't install packages"
   fi
fi

# We require jq >= 1.5 for --slurpfile for merging preferences. Debian Jessie ships with 1.4.
if cat /etc/os-release | grep 'PRETTY_NAME="Debian GNU/Linux 8 (jessie)"' &> /dev/null; then
   echo "Please consider upgrading your rig to Jubilinux 0.3.0 (Debian Stretch)!"
   sudo apt-get -y -t jessie-backports install jq || die "Couldn't install jq from jessie-backports"
else
   # Debian Stretch & Buster ship with jq >= 1.5, so install from apt
   sudo apt-get -y install jq || die "Couldn't install jq"
fi

# Install node using n if there is not an installed version of node >=8,<=19
# Edge case: This is not likely to work as expected if there *is* a version of node installed, but it is outside of the specified version constraints
if ! node --version | grep -q -e 'v[89]\.' -e 'v1[[:digit:]]\.'; then
   echo "Installing node via n..." # For context why we don't install using apt or nvm, see https://github.com/openaps/oref0/pull/1419
   curl -L https://raw.githubusercontent.com/tj/n/master/bin/n -o n
   # Install the latest compatible version of node
   sudo bash n current
   # Delete the local n binary used to boostrap the install
   rm n
   # Install n globally
   sudo npm install -g n
   
   # Upgrade to the latest supported version of npm for the current node version
   sudo npm upgrade -g npm|| die "Couldn't update npm"

   ## You may also need development tools to build native addons:
   ## sudo apt-get install gcc g++ make
fi

# upgrade setuptools to avoid "'install_requires' must be a string" error
sudo pip install setuptools -U # no need to die if this fails
sudo pip install -U --default-timeout=1000 git+https://github.com/openaps/openaps.git || die "Couldn't install openaps toolkit"
sudo pip install -U openaps-contrib || die "Couldn't install openaps-contrib"
sudo openaps-install-udev-rules || die "Couldn't run openaps-install-udev-rules"
sudo activate-global-python-argcomplete || die "Couldn't run activate-global-python-argcomplete"
sudo npm install -g json || die "Couldn't install npm json"
echo openaps installed
openaps --version
