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

. /home/yi-hack/base/script/get_config.sh
printf "Content-type: application/json\r\n\r\n"
PV=""; read PV 2>/dev/null < /home/yi-hack/config/privacy; [ -z "$PV" ] && PV=off
# Batch fork-free config reads via load_config. Pre-clear: a missing key must
# not leak an inherited env value (USER is in the CGI environment).
ENABLED=""; HOST=""; SHARE=""; USER=""; SSID=""
load_config cifs ENABLED HOST SHARE USER
load_config wifi SSID
printf '{"CIFS_ENABLED":"%s","CIFS_HOST":"%s","CIFS_SHARE":"%s","CIFS_USER":"%s","WIFI_SSID":"%s","PRIVACY":"%s"}' \
 "$ENABLED" "$HOST" "$SHARE" "$USER" "$SSID" "$PV"
