#!/bin/sh

#
#  This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
#  Copyright (c) 2026 Lino Barreca.
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, version 3.
#
#  This program is distributed in the hope that it will be useful, but
#  WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
#  General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program. If not, see <http://www.gnu.org/licenses/>.
#

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
