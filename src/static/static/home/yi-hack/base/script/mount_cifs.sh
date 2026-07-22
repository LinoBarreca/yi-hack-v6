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

# Batch fork-free read (one pass; the old per-key get_config subshells cost
# ~200ms each on this CPU). Pre-clear USER: it is in the boot environment.
ENABLED=""; HOST=""; SHARE=""; USER=""; PASS=""; SEC=""; VERS=""; RETRY=""; RETRY_DELAY=""
load_config cifs ENABLED HOST SHARE USER PASS SEC VERS RETRY RETRY_DELAY
[ "$ENABLED" = "yes" ] || { log "CIFS not enabled (cifs.ENABLED != yes)"; exit 1; }

[ -z "$USER" ] && USER=guest
[ -z "$SEC" ]  && SEC=ntlmssp
[ -z "$VERS" ] && VERS=1.0
case $RETRY       in ''|*[!0-9]*) RETRY=10 ;; esac
case $RETRY_DELAY in ''|*[!0-9]*) RETRY_DELAY=6 ;; esac

if [ -z "$HOST" ] || [ -z "$SHARE" ]; then
    log "HOST or SHARE not configured in cifs.conf"
    exit 1
fi

# Load the CIFS modules (idempotent: skip if already loaded)
for m in md4 hmac cifs; do
    if ! grep -q "^$m " /proc/modules; then
        _err=$(insmod "$KO_DIR/$m.ko" 2>&1) || log "warn: insmod $m.ko: ${_err:-failed} (maybe already loaded)"
    fi
done

mkdir -p "$MOUNTPOINT"

# If already mounted for some reason, unmount to start clean
grep -q " $MOUNTPOINT " /proc/mounts && { umount "$MOUNTPOINT" || log "WARNING: could not clear the existing mount on $MOUNTPOINT"; }

MODEL=""; read MODEL < /home/app/.camver

# Bound each attempt: a dead/unreachable server can hang mount(2) far longer than
# the whole retry budget. Guarded: older rootfs builds have no timeout applet.
T=""; command -v timeout >/dev/null && T="timeout 20"

i=0
while [ "$i" -lt "$RETRY" ]; do
    i=$((i + 1))
    # End-to-end verified options: SMB1/NT1 + NTLMv2, pass= (not password=), ro.
    # Capture stderr: the mount error is THE diagnostic and must reach the boot log.
    if _err=$($T mount -t cifs "//$HOST/$SHARE" "$MOUNTPOINT" \
            -o user="$USER",pass="$PASS",sec="$SEC",vers="$VERS",ro 2>&1); then
        log "mounted //$HOST/$SHARE on $MOUNTPOINT (attempt $i)"
        # Payload validation: look for the model tree, with a non-per-model fallback
        if [ -d "$MOUNTPOINT/$MODEL/yi-hack" ] || [ -d "$MOUNTPOINT/yi-hack" ]; then
            log "payload found on the share"
            exit 0
        fi
        log "mount OK but payload missing (looked for $MODEL/yi-hack and yi-hack)"
        umount "$MOUNTPOINT" || log "WARNING: umount $MOUNTPOINT failed, mount left behind"
        exit 2
    fi
    log "mount failed (attempt $i/$RETRY): ${_err:-timed out or unknown error} - retrying in ${RETRY_DELAY}s"
    sleep "$RETRY_DELAY"
done

log "giving up after $RETRY attempts -> minimal boot"
exit 1
