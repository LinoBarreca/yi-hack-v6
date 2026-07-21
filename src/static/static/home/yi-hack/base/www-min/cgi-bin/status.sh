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

printf "Content-type: application/json\r\n\r\n"
MODEL=$(cat /home/app/.camver 2>/dev/null)
WIP=$(ifconfig wlan0 2>/dev/null | awk '/inet addr/{print substr($2,6)}')
WMAC=$(cat /sys/class/net/wlan0/address 2>/dev/null)
EIP=$(ifconfig eth0 2>/dev/null | awk '/inet addr/{print substr($2,6)}')
EMAC=$(cat /sys/class/net/eth0/address 2>/dev/null)
SD=no; mount | grep -q ' /tmp/sd ' && SD=yes
CF=no; mount | grep -q ' /tmp/cifs-ro ' && CF=yes
if [ -L /home/yi-hack/extra ]; then EX=$(readlink /home/yi-hack/extra 2>/dev/null); else EX=none; fi
PV=$(cat /home/yi-hack/config/privacy 2>/dev/null); [ -z "$PV" ] && PV=off
printf '{"model":"%s","wifi_ip":"%s","wifi_mac":"%s","eth_ip":"%s","eth_mac":"%s","sd":"%s","cifs":"%s","extra":"%s","privacy":"%s"}' \
 "$MODEL" "$WIP" "$WMAC" "$EIP" "$EMAC" "$SD" "$CF" "$EX" "$PV"
