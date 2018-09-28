#!/bin/sh

# default enabling NTLM Authentication to enabled when unset
[ -z "$PT_enable_ntlm_authentication" ] && PT_enable_ntlm_authentication=true

cd /tmp

# Download the OMI server and PSRP packages
wget https://github.com/Microsoft/omi/releases/download/v1.5.0/omi-1.5.0-0.ssl_110.ulinux.x64.deb
wget https://github.com/PowerShell/psl-omi-provider/releases/download/v1.4.2-2/psrp-1.4.2-2.universal.x64.deb

# Install the new packages
dpkg -i omi-1.5.0-0.ssl_110.ulinux.x64.deb
dpkg -i psrp-1.4.2-2.universal.x64.deb

# Enable connectivity to 5986 through firewall
iptables -A INPUT -p tcp --dport 5986 -j ACCEPT

# Enable file based NTLM auth from
# https://github.com/Microsoft/omi/blob/master/Unix/doc/setup-ntlm-omi.md
if [ "$PT_enable_ntlm_authentication" = true ] ; then

  # Package dependencies
  apt-get install -y libgssapi-krb5-2 gss-ntlmssp
  # mechanism file at /etc/gss/mech.d/mech.ntlmssp.conf is already properly configured
  # gssntlmssp_v1           1.3.6.1.4.1.311.2.2.10          /usr/lib/x86_64-linux-gnu/gssntlmssp/gssntlmssp.so

  sed -i.bak \
     -e 's/^#NtlmCredsFile=.*/NtlmCredsFile=\/etc\/opt\/omi\/creds\/ntlm/g' \
     /etc/opt/omi/conf/omiserver.conf

  # setup the NTLM auth file with proper ownership and perms
  touch /etc/opt/omi/creds/ntlm
  chown -R omi:omi /etc/opt/omi/creds
  chmod 500 /etc/opt/omi/creds
  chmod 600 /etc/opt/omi/creds/ntlm

  # OMI server must be restarted for config changes to take effect
  /opt/omi/bin/service_control restart
fi
