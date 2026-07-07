#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# mount_cifs_rec.sh - mount the READ-WRITE CIFS share used by the native recorder
# (output.RECORD=CIFS). This is a SEPARATE share from the read-only firmware
# share handled by mount_cifs.sh (the payload is RO; recordings need RW).
#
# Parameters come from cifs.conf RECORDING_* fields. Any empty RECORDING_* field
# inherits the matching base field (HOST/SHARE/USER/PASS/SEC/VERS), so if the
# recordings live on the same server with the same credentials you only need to
# set RECORDING_SHARE. There is NO RECORDING_ENABLED: this script runs only when
# output.RECORD=CIFS.
#
# Invoked by S20yi-hack BEFORE build_view.sh (which then points output/record at
# this mount via CIFS_RW_MNT). WiFi is already up at this point.
#
# Exit: 0 = mounted RW  ->  echo the mountpoint on stdout for the caller
#       1 = disabled / not configured / failed

. /home/yi-hack/base/script/get_config.sh

MOUNTPOINT="/tmp/cifs_rec"
KO_DIR="/home/app/localko"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') mount_cifs_rec: $*" >&2; }

# Only when the recorder is configured to write to CIFS.
[ "$(get_config output.RECORD)" = "CIFS" ] || { log "output.RECORD != CIFS, nothing to mount"; exit 1; }

# RECORDING_<key> if set, else the base cifs.<key> (inherit-when-empty).
_p() {
    _v=$(get_config "cifs.RECORDING_$1")
    [ -n "$_v" ] && { echo "$_v"; return; }
    get_config "cifs.$1"
}

HOST=$(_p HOST)
SHARE=$(_p SHARE)
USER=$(_p USER);  [ -z "$USER" ] && USER=guest
PASS=$(_p PASS)
SEC=$(_p SEC);    [ -z "$SEC" ]  && SEC=ntlmssp
VERS=$(_p VERS);  [ -z "$VERS" ] && VERS=1.0
case $(get_config cifs.RETRY)       in ''|*[!0-9]*) RETRY=10 ;;      *) RETRY=$(get_config cifs.RETRY) ;; esac
case $(get_config cifs.RETRY_DELAY) in ''|*[!0-9]*) RETRY_DELAY=6 ;; *) RETRY_DELAY=$(get_config cifs.RETRY_DELAY) ;; esac

if [ -z "$HOST" ] || [ -z "$SHARE" ]; then
    log "recording share HOST or SHARE not configured (RECORDING_* / cifs.*)"
    exit 1
fi

# CIFS modules (idempotent).
for m in md4 hmac cifs; do
    if ! lsmod | grep -q "^$m "; then
        insmod "$KO_DIR/$m.ko" 2>/dev/null || log "warn: insmod $m.ko failed (maybe already loaded)"
    fi
done

mkdir -p "$MOUNTPOINT"
mount | grep -q " $MOUNTPOINT " && umount "$MOUNTPOINT" 2>/dev/null

i=0
while [ "$i" -lt "$RETRY" ]; do
    i=$((i + 1))
    # RW mount (no ,ro). Same SMB1/NTLMSSP options as the firmware share.
    if mount -t cifs "//$HOST/$SHARE" "$MOUNTPOINT" \
            -o user="$USER",pass="$PASS",sec="$SEC",vers="$VERS" 2>/dev/null; then
        # Verify it is actually writable (server-side perms / force user).
        if ( : > "$MOUNTPOINT/.wtest.$$" ) 2>/dev/null; then
            rm -f "$MOUNTPOINT/.wtest.$$"
            log "mounted RW //$HOST/$SHARE on $MOUNTPOINT (attempt $i)"
            echo "$MOUNTPOINT"
            exit 0
        fi
        log "mounted but NOT writable //$HOST/$SHARE (check server perms) -> giving up"
        umount "$MOUNTPOINT" 2>/dev/null
        exit 1
    fi
    log "mount failed (attempt $i/$RETRY), retrying in ${RETRY_DELAY}s"
    sleep "$RETRY_DELAY"
done

log "giving up after $RETRY attempts"
exit 1
