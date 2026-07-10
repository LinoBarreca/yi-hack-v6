#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# mount_cifs.sh - bootstrap CIFS mount for diskless (no-SD) operation.
#
# Invoked by /etc/init.d/S20yi-hack when there is no SD payload and CIFS is enabled
# in cifs.conf. At this point WiFi is ALREADY up (base/init.sh has run), so this
# script does NOT manage the network: it just waits for connectivity by retrying
# the mount itself.
#
# Responsibilities:
#   1. read parameters from cifs.conf (flash, via the centralized get_config)
#   2. insmod the CIFS modules (md4, hmac, cifs) - already present in flash
#   3. mount the share read-only on /tmp/cifs-ro with the verified-working SMB1/NTLMSSP options
#   4. validate that the model payload is present on the share
#
# /tmp/cifs-ro is the INPUT mount (payload/config). The OUTPUT (read-write) share
# is a separate mount, /tmp/cifs-rw, handled by mount_cifs_rw.sh.
#
# Exit code:
#   0 = mounted and payload present  -> caller proceeds to boot from CIFS
#   1 = disabled / not configured / failed after retries  -> minimal boot
#   2 = mounted but payload missing (wrong share?)         -> minimal boot
#
# HANDOFF NOTE: running the payload from /tmp/cifs-ro requires the logical
# view (no YI_HACK_PREFIX, /home/yi-hack/{config,extra,output}). This script only does
# mount + validation; build_view.sh wires extra->source and the dispatcher boots it.

# Bootstrap config: in FLASH, read before any payload mount.
. /home/yi-hack/base/script/get_config.sh

MOUNTPOINT="/tmp/cifs-ro"
KO_DIR="/home/app/localko"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') mount_cifs: $*"; }

[ "$(get_config cifs.ENABLED)" = "yes" ] || { log "CIFS not enabled (cifs.ENABLED != yes)"; exit 1; }

HOST=$(get_config cifs.HOST)
SHARE=$(get_config cifs.SHARE)
USER=$(get_config cifs.USER);  [ -z "$USER" ] && USER=guest
PASS=$(get_config cifs.PASS)
SEC=$(get_config cifs.SEC);    [ -z "$SEC" ]  && SEC=ntlmssp
VERS=$(get_config cifs.VERS);  [ -z "$VERS" ] && VERS=1.0
case $(get_config cifs.RETRY)       in ''|*[!0-9]*) RETRY=10 ;;       *) RETRY=$(get_config cifs.RETRY) ;; esac
case $(get_config cifs.RETRY_DELAY) in ''|*[!0-9]*) RETRY_DELAY=6 ;;  *) RETRY_DELAY=$(get_config cifs.RETRY_DELAY) ;; esac

if [ -z "$HOST" ] || [ -z "$SHARE" ]; then
    log "HOST or SHARE not configured in cifs.conf"
    exit 1
fi

# Load the CIFS modules (idempotent: skip if already loaded)
for m in md4 hmac cifs; do
    if ! lsmod | grep -q "^$m "; then
        insmod "$KO_DIR/$m.ko" 2>/dev/null || log "warn: insmod $m.ko failed (maybe already loaded)"
    fi
done

mkdir -p "$MOUNTPOINT"

# If already mounted for some reason, unmount to start clean
mount | grep -q " $MOUNTPOINT " && umount "$MOUNTPOINT" 2>/dev/null

MODEL=$(cat /home/app/.camver 2>/dev/null)

i=0
while [ "$i" -lt "$RETRY" ]; do
    i=$((i + 1))
    # End-to-end verified options: SMB1/NT1 + NTLMv2, pass= (not password=), ro
    if mount -t cifs "//$HOST/$SHARE" "$MOUNTPOINT" \
            -o user="$USER",pass="$PASS",sec="$SEC",vers="$VERS",ro 2>/dev/null; then
        log "mounted //$HOST/$SHARE on $MOUNTPOINT (attempt $i)"
        # Payload validation: look for the model tree, with a non-per-model fallback
        if [ -d "$MOUNTPOINT/$MODEL/yi-hack" ] || [ -d "$MOUNTPOINT/yi-hack" ]; then
            log "payload found on the share"
            exit 0
        fi
        log "mount OK but payload missing (looked for $MODEL/yi-hack and yi-hack)"
        umount "$MOUNTPOINT" 2>/dev/null
        exit 2
    fi
    log "mount failed (attempt $i/$RETRY), retrying in ${RETRY_DELAY}s"
    sleep "$RETRY_DELAY"
done

log "giving up after $RETRY attempts -> minimal boot"
exit 1
