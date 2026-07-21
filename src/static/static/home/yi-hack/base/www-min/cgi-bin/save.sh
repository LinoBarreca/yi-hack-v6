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

. /home/yi-hack/base/www-min/cgi-bin/rescue_lib.sh
read_body
printf "Content-type: application/json\r\n\r\n"
setkey cifs.conf ENABLED "$(get_field cifs_enabled)"
setkey cifs.conf HOST    "$(get_field cifs_host)"
setkey cifs.conf SHARE   "$(get_field cifs_share)"
setkey cifs.conf USER    "$(get_field cifs_user)"
S=$(get_field wifi_ssid); P=$(get_field wifi_psk)
[ -n "$S" ] && setkey wifi.conf SSID "$S"
[ -n "$P" ] && setkey wifi.conf PSK "$P"
# wifi.conf is applied to the radio at next boot by wifi_up.sh (S20): it writes the new
# SSID/PSK into mtdblock2[28/92] and associates. Not applied live here on purpose, to avoid
# dropping the rescue session mid-config -> reboot to apply.
if [ "$(get_field privacy)" = "on" ]; then echo on > "$CONFIG/privacy"; else rm -f "$CONFIG/privacy"; fi
sync
printf '{"error":"false"}'
