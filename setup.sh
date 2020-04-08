#! /usr/bin/env bash

mkdir -p /tmp/tersync &&
cd /tmp/tersync &&
rm -f tersync.sh &> /dev/null &&
wget https://raw.githubusercontent.com/annahri/tersync/master/tersync.sh &&
install tersync.sh /usr/local/bin/tersync.sh &&
echo "tersync.sh has been installed in /usr/local/bin/tersync.sh" ||
echo "unable to install tersync.sh"
