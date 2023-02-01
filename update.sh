#!/bin/bash

# To run ubiquity commands
run=/opt/vyatta/bin/vyatta-op-cmd-wrapper

# Generic binaries
echo "Installing nano and dnsutils"
apt-get update
apt-get install -y nano dnsutils libdata-validate-ip-perl

# Install ddclient
echo "Installing ddclient"
 curl -sL https://raw.githubusercontent.com/ddclient/ddclient/6ae69a1ce688e8212b0973867b16af37f85172ef/ddclient -o /usr/sbin/ddclient
echo "Updating ddns data"
$run show dns dynamic status
$run update dns dynamic interface pppoe2
$run show dns dynamic status

# Install dnscrypt
echo "Installing dnscrypt"
curl -sL https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.2/dnscrypt-proxy-linux_mips64-2.1.2.tar.gz -o dnscrypt.tar.gz
mkdir /opt/dnscrypt
tar -xzf dnscrypt.tar.gz
mv linux-mips64/dnscrypt-proxy /opt/dnscrypt/
chmod +x /opt/dnscrypt/dnscrypt-proxy
/opt/dnscrypt/dnscrypt-proxy -config /config/dns/dnscrypt-proxy.toml -service install
rm -rf linux-mips64/
rm dnscrypt.tar.gz

# Install wireguard
echo "Installing wireguard"
curl -sL https://github.com/WireGuard/wireguard-vyatta-ubnt/releases/download/1.0.20200506-1/ugw4-v1-v1.0.20200506-v1.0.20200319.deb -o wg.deb
dpkg -i wg.deb
rm wg.deb

echo "Done, please reboot!"
