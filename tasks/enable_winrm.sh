#!/bin/sh

# default enabling NTLM Authentication to enabled when unset
[ -z "$PT_enable_ntlm_authentication" ] && PT_enable_ntlm_authentication=true

# default is to not build OMI from source
[ -z "$PT_build_omi" ] && PT_build_omi=false

if [ "$PT_build_omi" = true ] ; then
  # 18.04 includes the needed libgssapi-krb5-2 1.14+
  apt-get install -y git pkg-config make g++ rpm librpm-dev libpam0g-dev libssl-dev libkrb5-dev libgssapi-krb5-2 gawk python selinux-policy-dev

  # Clone openssl sources
  cd /tmp
  git clone https://github.com/openssl/openssl

  # Build OpenSSL 1.0.0
  cd /tmp/openssl/
  git checkout OpenSSL_1_0_0
  ./config --prefix=/usr/local_ssl_1.0.0 shared -no-ssl2 -no-ec -no-ec2m -no-ecdh
  make clean && make depend && make && make install_sw

  # Build OpenSSL 1.1.0
  cd /tmp/openssl/
  git checkout OpenSSL_1_1_0
  ./config --prefix=/usr/local_ssl_1.1.0 shared -no-ssl2 -no-ec -no-ec2m -no-ecdh
  make clean && make depend && make && make install_sw

  # Clone OMI sources
  cd /tmp
  git clone https://github.com/Microsoft/Build-omi
  cd Build-omi
  git clone https://github.com/Microsoft/omi
  git clone https://github.com/Microsoft/pal
  git submodule foreach git checkout master

  # Build OMI master without openssl 0.9.8 packages
  cd /tmp/Build-omi/omi/Unix
  ./configure --enable-system-build --enable-native-kits --disable-ssl-0.9.8
  make

  OMI_PKG=/tmp/Build-omi/omi/Unix/output_openssl_1.1.0/release/omi-1.4.3-*.ssl_110.ulinux.x64.deb
else
  OMI_PKG=omi-1.5.0-0.ssl_110.ulinux.x64.deb

  wget https://github.com/Microsoft/omi/releases/download/v1.5.0/$OMI_PKG --directory-prefix=/tmp
fi

# install OMI server
cd /tmp
dpkg -i $OMI_PKG

# make sure https listener is configured on 5986
sed -i.bak \
   -e 's/^#\?httpsport=.*/httpsport=0,5986/g' \
   /etc/opt/omi/conf/omiserver.conf

# Download the PSRP package and install
wget https://github.com/PowerShell/psl-omi-provider/releases/download/v1.4.2-2/psrp-1.4.2-2.universal.x64.deb
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

  sed -i.bak2 \
     -e 's/^#NtlmCredsFile=.*/NtlmCredsFile=\/etc\/opt\/omi\/creds\/ntlm/g' \
     /etc/opt/omi/conf/omiserver.conf

  # setup the NTLM auth file with proper ownership and perms
  touch /etc/opt/omi/creds/ntlm
  chown -R omi:omi /etc/opt/omi/creds
  chmod 500 /etc/opt/omi/creds
  chmod 600 /etc/opt/omi/creds/ntlm
fi

# OMI server must be restarted for config changes to take effect
/opt/omi/bin/service_control restart
