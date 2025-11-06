#!/usr/bin/env bash

source $(dirname $0)/oref0-bash-common-functions.sh || (echo "ERROR: Failed to run oref0-bash-common-functions.sh. Is oref0 correctly installed?"; exit 1)

usage "$@" <<EOT
Usage: $self

Install development tools and download source code to OpenAPS projects from
GitHub to ~/src. This is not run as part of a normal end-user setup of OpenAPS,
but may be useful for developers or for advanced troubleshooting.
EOT

# Note: Run openaps-packages.sh first to install Python 2.7 and pip2 on modern systems (Bookworm+)
apt-get install -y sudo
sudo apt-get update
sudo apt-get install -y git nodejs-legacy npm watchdog strace tcpdump screen acpid vim locate jq lm-sensors && \
( curl -s https://bootstrap.pypa.io/pip/2.7/get-pip.py | sudo python2 ) && \
sudo npm install -g json && \
sudo easy_install -ZU setuptools && \
mkdir ~/src
cd ~/src && \
(
    git clone -b dev https://github.com/openaps/decocare.git || \
        (cd decocare && git pull)
    (cd decocare && \
        sudo python2 setup.py develop
    )
    git clone https://github.com/openaps/dexcom_reader.git || \
        (cd dexcom_reader && git pull)
    (cd dexcom_reader && \
        sudo python2 setup.py develop
    )
    git clone -b dev https://github.com/openaps/openaps.git || \
        (cd openaps && git pull)
    (cd openaps && \
        sudo python2 setup.py develop
    )
    git clone https://github.com/openaps/openaps-contrib.git || \
        (cd openaps-contrib && git pull)
    (cd openaps-contrib && \
        sudo python2 setup.py develop
    )
    git clone -b dev https://github.com/lukaszarczynski/oref0.git || \
        (cd oref0 && git pull)
)
test -d oref0 && \
cd oref0 && \
npm install && \
sudo npm install -g && \
sudo npm link && \
sudo npm link oref0

sudo openaps-install-udev-rules && \
sudo activate-global-python-argcomplete && \
openaps --version
