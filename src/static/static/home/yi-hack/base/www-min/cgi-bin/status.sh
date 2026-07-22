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
# Single-line files via the read builtin (no $(cat) forks); one builtin pass
# over /proc/mounts instead of mount|grep (never stat the mounts - SMB1).
MODEL=""; WMAC=""; EMAC=""; PV=""
read MODEL < /home/app/.camver
WIP=$(ifconfig wlan0 2>/dev/null | awk '/inet addr/{print substr($2,6)}')
read WMAC < /sys/class/net/wlan0/address
EIP=$(ifconfig eth0 2>/dev/null | awk '/inet addr/{print substr($2,6)}')
read EMAC < /sys/class/net/eth0/address
SD=no; CF=no
while read -r _dev _mnt _; do
    case "$_mnt" in
        /tmp/sd)      SD=yes ;;
        /tmp/cifs-ro) CF=yes ;;
    esac
done < /proc/mounts
if [ -L /home/yi-hack/extra ]; then EX=$(readlink /home/yi-hack/extra 2>/dev/null); else EX=none; fi
read PV 2>/dev/null < /home/yi-hack/config/privacy; [ -z "$PV" ] && PV=off
printf '{"model":"%s","wifi_ip":"%s","wifi_mac":"%s","eth_ip":"%s","eth_mac":"%s","sd":"%s","cifs":"%s","extra":"%s","privacy":"%s"}' \
 "$MODEL" "$WIP" "$WMAC" "$EIP" "$EMAC" "$SD" "$CF" "$EX" "$PV"
