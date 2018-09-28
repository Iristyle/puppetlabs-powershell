#!/bin/sh

# default ssh remoting to enabled when unset
[ -z "$PT_enable_ssh_remoting" ] && PT_enable_ssh_remoting=true

# https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-powershell-core-on-linux?view=powershell-6

# .NET core dependencies
apt-get install -y libc6 libgcc1 libgssapi-krb5-2 liblttng-ust0 libstdc++6 libcurl3 libunwind8 libuuid1 zlib1g libssl1.0.0 libicu60

# Download and register Microsoft GPG keys
wget https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb

# Update sources and install PowerShell
apt-get update && apt-get install -y powershell
# binary releases available at https://github.com/PowerShell/PowerShell/releases/latest

# Enable Enter-PSSession to be used against this host
# https://docs.microsoft.com/en-us/powershell/scripting/core-powershell/ssh-remoting-in-powershell-core?view=powershell-6#set-up-on-linux-ubuntu-1404-machine
if [ "$PT_enable_ssh_remoting" = true ] ; then
  sed -i.bak \
         -e 's/^#?PermitEmptyPasswords .*/PermitEmptyPasswords no/g' \
         -e 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/g' \
         /etc/ssh/sshd_config

  grep -q -F 'Subsystem\s*powershell' /etc/ssh/sshd_config
  if [ $? -ne 0 ]; then
    echo 'Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile' >> /etc/ssh/sshd_config
  fi

  # SSH service must be restarted for config changes to take effect
  service sshd restart
fi
