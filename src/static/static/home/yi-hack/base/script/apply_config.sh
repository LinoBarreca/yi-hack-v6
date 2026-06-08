#!/bin/sh

# 0.1.0 - yi-hack-v6
#
# apply_config.sh - apply managed config overrides from the payload share into the
# flash config/ (section 6.2). A config file present on the share is "managed
# centrally" and is copied OVER the local flash copy, per-file, RECURSIVELY (so
# config/services/*.conf are handled too). This enables mass migration.
#
# Runs in base/flash AFTER mount_cifs.sh (mount done) and BEFORE build_view.sh /
# the dispatcher, so everything downstream reads the overridden values.
#
# Source priority mirrors build_view.sh: CIFS (if enabled+mounted) else SD. The
# managed config lives in the SAME payload tree as extra: <payload>/config
# (per-model first, then flat), e.g. /tmp/cifs/yi-hack/config/.
#
# HARD EXCLUSIONS (class 2b runtime state, 6.2/6.7): camera.conf and
# ptz_presets.conf are written by the device and are NEVER overridden (an override
# would wipe runtime state every boot).
#
# KISS: no validation/rollback (section 10) - a bad managed value just propagates;
# never fails the boot (always exit 0).
#
# Test overrides: LOGICAL, SD_MNT, CIFS_MNT, CONFIG_DIR

LOGICAL="${LOGICAL:-/home/yi-hack}"
SD_MNT="${SD_MNT:-/tmp/sd}"
CIFS_MNT="${CIFS_MNT:-/tmp/cifs}"
CONFIG_DIR="${CONFIG_DIR:-$LOGICAL/config}"
. "$LOGICAL/base/script/get_config.sh"
. "$LOGICAL/base/script/version_compat.sh"

MODEL=$(cat /home/app/.camver 2>/dev/null)
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') apply_config: $*"; }
is_mounted() { mount 2>/dev/null | grep -q " $1 "; }

# Never overridden from the share:
#  - camera.conf / ptz_presets.conf : runtime state written by the device (6.7)
#  - identity.conf / hostname        : per-camera identity (5.7) - a mass push would
#                                      make cameras collide (same HA device / MQTT
#                                      client id / topic prefix / hostname)
EXCLUDE="camera.conf ptz_presets.conf identity.conf hostname"

# Path of the managed config dir on a mounted source: per-model then flat.
config_on() {
    for _c in "$1/$MODEL/yi-hack/config" "$1/yi-hack/$MODEL/config" "$1/yi-hack/config"; do
        [ -d "$_c" ] && { echo "$_c"; return 0; }
    done
    return 1
}

SRC=""
if [ "$(get_config cifs.ENABLED)" = "yes" ] && is_mounted "$CIFS_MNT"; then
    SRC=$(config_on "$CIFS_MNT") && log "managed config <- CIFS ($SRC)"
fi
if [ -z "$SRC" ] && is_mounted "$SD_MNT"; then
    SRC=$(config_on "$SD_MNT") && log "managed config <- SD ($SRC)"
fi
[ -z "$SRC" ] && { log "no managed config on share -> keep flash defaults"; exit 0; }

# Version handshake (5.8): never apply managed config from an incompatible payload
# (wrong config schema would push bad settings).
if ! payload_compatible "${SRC%/*}"; then
    log "payload incompatible with base -> NOT applying managed config"
    exit 0
fi

# Copy each file over flash, preserving the relative path (recursive), skipping the
# runtime-state exclusions. Parameter expansion only (no basename/dirname applet).
( cd "$SRC" 2>/dev/null && find . -type f ) | while IFS= read -r f; do
    rel=${f#./}
    base=${rel##*/}
    case " $EXCLUDE " in *" $base "*) log "skip $rel (runtime state, never overridden)"; continue ;; esac
    dest="$CONFIG_DIR/$rel"
    mkdir -p "${dest%/*}"
    if cp "$SRC/$rel" "$dest"; then log "override $rel"; else log "FAILED $rel"; fi
done

exit 0
