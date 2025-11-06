#!/usr/bin/env bash

die() {
    echo "$@"
    exit 1
}

# TODO: remove the `Acquire::ForceIPv4=true` once Debian's mirrors work reliably over IPv6
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4

apt-get install -y sudo
sudo apt-get update && sudo apt-get -y upgrade

# Detect Python version and set pip flags
PIP_BREAK_SYSTEM=""
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
      sudo apt-get install -y git python-is-python3 python3-dev python3-full software-properties-common python3-numpy python3-pip watchdog strace tcpdump screen acpid vim locate lm-sensors bc || die "Couldn't install packages"
      # Bookworm+ has PEP 668 externally-managed-environment protection
      # For dedicated embedded systems like OpenAPS rigs, we need --break-system-packages
      PIP_BREAK_SYSTEM="--break-system-packages"

      # Install Python 2.7 for deprecated openaps package (Python 2 syntax incompatible with Python 3)
      echo "Installing Python 2.7 and pip2 for openaps package..."
      if ! command -v python2.7 &> /dev/null; then
         echo "Python 2.7 not found, attempting to install..."
         # Try to install from package manager first
         sudo apt-get install -y python2.7 2>/dev/null
         # Verify that python2.7 actually works (apt might install just the library)
         if command -v python2.7 &> /dev/null && python2.7 --version &> /dev/null; then
            echo "Python 2.7 installed from package manager"
         else
            echo "Python 2.7 not available in repos, building from source..."
            # Install build dependencies
            sudo apt-get install -y build-essential libssl-dev zlib1g-dev libncurses5-dev \
                libncursesw5-dev libreadline-dev libsqlite3-dev libgdbm-dev libdb5.3-dev \
                libbz2-dev libexpat1-dev liblzma-dev tk-dev libffi-dev || die "Couldn't install build dependencies"

            # Download and compile Python 2.7.18 (final Python 2 release)
            cd /tmp
            wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz || die "Couldn't download Python 2.7.18"
            tar -xzf Python-2.7.18.tgz
            cd Python-2.7.18
            ./configure --enable-optimizations --prefix=/usr/local || die "Couldn't configure Python 2.7.18"
            make -j$(nproc) || die "Couldn't compile Python 2.7.18"
            sudo make altinstall || die "Couldn't install Python 2.7.18"
            cd /tmp
            rm -rf Python-2.7.18 Python-2.7.18.tgz
            echo "Python 2.7.18 compiled and installed from source"
         fi
      fi

      # Create python2 symlink if it doesn't exist
      if ! command -v python2 &> /dev/null; then
         sudo ln -sf /usr/local/bin/python2.7 /usr/local/bin/python2 || sudo ln -sf /usr/bin/python2.7 /usr/local/bin/python2
      fi

      # Install pip for Python 2.7
      if ! command -v pip2 &> /dev/null && ! command -v pip2.7 &> /dev/null; then
         echo "Installing pip for Python 2.7..."
         curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -o /tmp/get-pip.py
         sudo python2.7 /tmp/get-pip.py || die "Couldn't install pip2"
         rm /tmp/get-pip.py
         # Create pip2 symlink if needed
         if ! command -v pip2 &> /dev/null && command -v pip2.7 &> /dev/null; then
            sudo ln -sf $(which pip2.7) /usr/local/bin/pip2
         fi
      fi
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
if ! node --version 2>/dev/null | grep -q -e 'v[89]\.' -e 'v1[0-9]\.'; then
   echo "Installing node via n..." # For context why we don't install using apt or nvm, see https://github.com/openaps/oref0/pull/1419
   curl -L https://raw.githubusercontent.com/tj/n/master/bin/n -o n
   # Install Node 19 (last version in the acceptable range >=8,<=19)
   sudo bash n 19
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
# Use pip3 explicitly on modern systems, pip on old systems
if [ -n "$PIP_BREAK_SYSTEM" ]; then
    sudo pip3 install $PIP_BREAK_SYSTEM setuptools -U # no need to die if this fails
else
    sudo pip install setuptools -U # no need to die if this fails
fi
sudo npm install -g json || die "Couldn't install npm json"
echo oref0 dependencies installed
