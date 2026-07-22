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
#
# cifstest.sh (full UI) - validate a CIFS share on a TEMPORARY mountpoint
# without touching the live /tmp/cifs-ro / /tmp/cifs-rw mounts.
#
#   ?share=ro   test the firmware share (read-only + payload present)
#   ?share=rw   test the output share (read-write + write test; RW_* fields
#               inherit the firmware share fields when empty, like mount_cifs_rw)
#
# Values are read from the CURRENT cifs.conf (save first, then test).

. /home/yi-hack/base/script/get_config.sh

SHARE_KIND=""
OIFS=$IFS; IFS='&'
for _kv in $QUERY_STRING; do
    case "$_kv" in share=*) SHARE_KIND=$(printf '%s' "${_kv#*=}" | tr -cd 'a-z'); break ;; esac
done
IFS=$OIFS
[ "$SHARE_KIND" = "rw" ] || SHARE_KIND="ro"

MP=/tmp/cifs_check
out() { printf '{"ok":"%s","msg":"%s"}' "$1" "$2"; }

printf "Content-type: application/json\r\n\r\n"

# Batch fork-free config read; RW_<key> wins over the base cifs.<key> when set
# (inherit-when-empty, same rule as mount_cifs_rw.sh). Pre-clear USER: CGI env.
HOST=""; SHARE=""; USER=""; PASS=""; SEC=""; VERS=""
RW_HOST=""; RW_SHARE=""; RW_USER=""; RW_PASS=""; RW_SEC=""; RW_VERS=""
if [ "$SHARE_KIND" = "rw" ]; then
    load_config cifs HOST SHARE USER PASS SEC VERS \
                     RW_HOST RW_SHARE RW_USER RW_PASS RW_SEC RW_VERS
    if [ -z "$RW_HOST" ] && [ -z "$RW_SHARE" ]; then
        out no "Output share not configured (set the share and/or server first, then save)."; exit 0
    fi
    [ -n "$RW_HOST" ]  && HOST=$RW_HOST
    [ -n "$RW_SHARE" ] && SHARE=$RW_SHARE
    [ -n "$RW_USER" ]  && USER=$RW_USER
    [ -n "$RW_PASS" ]  && PASS=$RW_PASS
    [ -n "$RW_SEC" ]   && SEC=$RW_SEC
    [ -n "$RW_VERS" ]  && VERS=$RW_VERS
else
    load_config cifs HOST SHARE USER PASS SEC VERS
fi
[ -z "$USER" ] && USER=guest
[ -z "$SEC" ]  && SEC=ntlmssp
[ -z "$VERS" ] && VERS=1.0

if [ -z "$HOST" ] || [ -z "$SHARE" ]; then
    out no "Server and share name are required (save the settings first)."; exit 0
fi

# insmod/umount errors go to the httpd log rather than /dev/null: when the
# mount below fails, the real cause is usually here (missing .ko for this
# model, or a stale mount that could not be cleared).
for m in md4 hmac cifs; do grep -q "^$m " /proc/modules || insmod /home/app/localko/$m.ko; done
mkdir -p "$MP"; grep -q " $MP " /proc/mounts && umount "$MP"

RO_OPT=",ro"; [ "$SHARE_KIND" = "rw" ] && RO_OPT=""
# timeout: a dead/unreachable server must produce an answer, not a hung CGI
if ! timeout 15 mount -t cifs "//$HOST/$SHARE" "$MP" \
        -o user="$USER",pass="$PASS",sec="$SEC",vers="$VERS"$RO_OPT 2>/tmp/cifstest.err; then
    ERR=$(tr -d '"\n' < /tmp/cifstest.err | cut -c1-160)
    out no "Mount failed: ${ERR:-timed out (server unreachable?)}"; exit 0
fi

if [ "$SHARE_KIND" = "rw" ]; then
    if ( : > "$MP/.wtest.$$" ) 2>/dev/null; then
        rm -f "$MP/.wtest.$$"
        out yes "Mounted read-write and verified writable."
    else
        out no "Mounted, but NOT writable (check the share permissions on the server)."
    fi
else
    MODEL=""; read MODEL < /home/app/.camver
    if [ -d "$MP/$MODEL/yi-hack" ] || [ -d "$MP/yi-hack" ]; then
        out yes "Mounted and the Yi-Hack firmware was found on the share."
    else
        out no "Mounted, but the Yi-Hack firmware (yi-hack/) was not found on the share."
    fi
fi
umount "$MP"
exit 0
