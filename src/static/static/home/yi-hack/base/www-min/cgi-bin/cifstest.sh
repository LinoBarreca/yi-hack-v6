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

# Validate CIFS while the SD is still inserted: mount on a TEMP mountpoint,
# check the payload, unmount. Does not touch /tmp/cifs-ro or the running config.
. /home/yi-hack/base/www-min/cgi-bin/rescue_lib.sh
read_body
printf "Content-type: application/json\r\n\r\n"
HOST=$(get_field cifs_host); SHARE=$(get_field cifs_share)
USER=$(get_field cifs_user); [ -z "$USER" ] && USER=guest
MP=/tmp/cifs_check

if [ -z "$HOST" ] || [ -z "$SHARE" ]; then printf '{"ok":"no","msg":"Host and Share are required."}'; exit; fi

for m in md4 hmac cifs; do lsmod | grep -q "^$m " || insmod /home/app/localko/$m.ko 2>/dev/null; done
mkdir -p "$MP"; mount | grep -q " $MP " && umount "$MP" 2>/dev/null

if mount -t cifs "//$HOST/$SHARE" "$MP" -o user="$USER",pass=,sec=ntlmssp,vers=1.0,ro 2>/tmp/cifstest.err; then
    MODEL=$(cat /home/app/.camver 2>/dev/null)
    if [ -d "$MP/$MODEL/yi-hack" ] || [ -d "$MP/yi-hack" ]; then
        printf '{"ok":"yes","msg":"Mount OK and payload found on the share."}'
    else
        printf '{"ok":"no","msg":"Mounted, but payload (yi-hack/) not found on the share."}'
    fi
    umount "$MP" 2>/dev/null
else
    ERR=$(tr -d '"\n' < /tmp/cifstest.err | cut -c1-160)
    printf '{"ok":"no","msg":"Mount failed: %s"}' "$ERR"
fi
