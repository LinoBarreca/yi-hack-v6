#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# mount_cifs_rw.sh - mount the READ-WRITE CIFS share used for outputs (recordings,
# service logs - any output.* category set to CIFS). This is a SEPARATE mount from
# the read-only firmware share handled by mount_cifs.sh:
#
#   /tmp/cifs-ro  = input  (payload/config, RO)   - mount_cifs.sh
#   /tmp/cifs-rw  = output (record/log, RW)       - this script
#
# Parameters come from cifs.conf RW_* fields. The share is considered CONFIGURED
# when RW_HOST or RW_SHARE is set; any other empty RW_* field inherits the matching
# base field (HOST/SHARE/USER/PASS/SEC/VERS), so if the outputs live on the same
# server with the same credentials you only need to set RW_SHARE. When configured,
# the share is ALWAYS mounted at boot (not gated on output.RECORD: build_view routes
# any output category to it, e.g. LOG=CIFS without RECORD=CIFS).
#
# Invoked by S20yi-hack BEFORE build_view.sh (which then points output/* views at
# this mount via CIFS_RW_MNT). WiFi is already up at this point.
#
# Exit: 0 = mounted RW  ->  echo the mountpoint on stdout for the caller
#       1 = not configured / failed

. /home/yi-hack/base/script/get_config.sh

MOUNTPOINT="/tmp/cifs-rw"
KO_DIR="/home/app/localko"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') mount_cifs_rw: $*" >&2; }

# Configured = the user declared a distinct RW share (host and/or share name).
# Without this, inheritance would silently RW-mount the firmware share every boot.
RW_HOST=$(get_config cifs.RW_HOST)
RW_SHARE=$(get_config cifs.RW_SHARE)
if [ -z "$RW_HOST" ] && [ -z "$RW_SHARE" ]; then
    log "RW share not configured (RW_HOST/RW_SHARE empty), nothing to mount"
    exit 1
fi

# RW_<key> if set, else the base cifs.<key> (inherit-when-empty).
_p() {
    _v=$(get_config "cifs.RW_$1")
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
    log "RW share HOST or SHARE still empty after inheritance (RW_* / cifs.*)"
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
