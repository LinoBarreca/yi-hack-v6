#!/bin/sh

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

if [ "$SHARE_KIND" = "rw" ]; then
    _p() { _v=$(get_config "cifs.RW_$1"); [ -n "$_v" ] && { echo "$_v"; return; }; get_config "cifs.$1"; }
    HOST=$(_p HOST); SHARE=$(_p SHARE); USER=$(_p USER); PASS=$(_p PASS)
    SEC=$(_p SEC);   VERS=$(_p VERS)
    RW_HOST=$(get_config cifs.RW_HOST); RW_SHARE=$(get_config cifs.RW_SHARE)
    if [ -z "$RW_HOST" ] && [ -z "$RW_SHARE" ]; then
        out no "Output share not configured (set the share and/or server first, then save)."; exit 0
    fi
else
    HOST=$(get_config cifs.HOST);  SHARE=$(get_config cifs.SHARE)
    USER=$(get_config cifs.USER);  PASS=$(get_config cifs.PASS)
    SEC=$(get_config cifs.SEC);    VERS=$(get_config cifs.VERS)
fi
[ -z "$USER" ] && USER=guest
[ -z "$SEC" ]  && SEC=ntlmssp
[ -z "$VERS" ] && VERS=1.0

if [ -z "$HOST" ] || [ -z "$SHARE" ]; then
    out no "Server and share name are required (save the settings first)."; exit 0
fi

for m in md4 hmac cifs; do grep -q "^$m " /proc/modules || insmod /home/app/localko/$m.ko 2>/dev/null; done
mkdir -p "$MP"; grep -q " $MP " /proc/mounts && umount "$MP" 2>/dev/null

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
    MODEL=$(cat /home/app/.camver 2>/dev/null)
    if [ -d "$MP/$MODEL/yi-hack" ] || [ -d "$MP/yi-hack" ]; then
        out yes "Mounted and the Yi-Hack firmware was found on the share."
    else
        out no "Mounted, but the Yi-Hack firmware (yi-hack/) was not found on the share."
    fi
fi
umount "$MP" 2>/dev/null
exit 0
