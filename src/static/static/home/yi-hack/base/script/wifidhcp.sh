#!/bin/sh

# 0.1.0

killall udhcpc
HN="yi-hack-v6"
if [ -f /home/yi-hack/config/hostname ]; then
        HN=$(cat /home/yi-hack/config/hostname)
fi
/sbin/udhcpc -i wlan0 -b -s /home/app/script/default.script -x hostname:$HN
