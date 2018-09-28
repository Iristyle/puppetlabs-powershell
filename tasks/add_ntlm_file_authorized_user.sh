#!/bin/sh

echo ":$PT_username:$PT_password" >> /etc/opt/omi/creds/ntlm
echo "$(hostname):$PT_username:$PT_password" >> /etc/opt/omi/creds/ntlm
echo "$(nslookup $(hostname) | awk '/^Address: / { print $2 }'):$PT_username:$PT_password" >> /etc/opt/omi/creds/ntlm

chown -R omi:omi /etc/opt/omi/creds
chmod 600 /etc/opt/omi/creds/ntlm
