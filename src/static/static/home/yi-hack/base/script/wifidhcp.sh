#!/bin/sh

# 6.0.1

killall udhcpc

# Configured hostname (may be blank until set_defaults fills it on first boot).
HN=""
[ -f /home/yi-hack/config/hostname ] && HN=$(cat /home/yi-hack/config/hostname)

# -O hostname : request the DHCP server's host-name option (12), so a DHCP-assigned
#               name can seed a blank hostname - default.script applies $hostname.
# -x hostname : advertise our own hostname to the server, only when one is set (an
#               empty/shared default like "yi-hack-v6" would make every camera
#               register under the same name).
if [ -n "$HN" ]; then
    /sbin/udhcpc -i wlan0 -b -O hostname -s /home/app/script/default.script -x hostname:"$HN"
else
    /sbin/udhcpc -i wlan0 -b -O hostname -s /home/app/script/default.script
fi
