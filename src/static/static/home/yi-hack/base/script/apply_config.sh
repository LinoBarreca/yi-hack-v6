#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# apply_config.sh - apply managed config overrides from the payload share into the
# flash config/. A config file present on the share is "managed
# centrally" and is copied OVER the local flash copy, per-file, RECURSIVELY (so
# config/services/*.conf are handled too). This enables mass migration.
#
# Run TWICE by S20yi-hack: once BEFORE mount_cifs.sh (only the SD is mounted -> applies
# the SD config, incl. cifs.conf, so mount_cifs can reach the share) and once AFTER (the
# CIFS, having priority, overrides). Source priority mirrors build_view.sh: CIFS (if
# enabled+mounted) else SD. The managed config lives in the SAME payload tree as extra:
# <payload>/config (per-model first, then flat), e.g. /tmp/cifs-ro/yi-hack/config/.
#
# EVERYTHING is version-gated: the flash base and the share payload must share the
# same MAJOR.MINOR, else NOTHING is applied -> flash base+config stay ALIGNED (a newer
# payload, e.g. 6.2.0, never pushes its config onto an older 6.0.1 base, which would
# brick). No exemptions: a provisioning SD must carry a matching <root>/version. The SD's
# version is local (SD mounted first), so even cifs.conf can be gated without a chicken-egg.
#
# HARD EXCLUSIONS (runtime state): camera.conf and ptz_presets.conf are written by the
# device and are NEVER overridden (an override would wipe runtime state every boot).
#
# KISS: no validation/rollback - a bad managed value just propagates;
# never fails the boot (always exit 0).
#
# Test overrides: LOGICAL, SD_MNT, CIFS_MNT, CONFIG_DIR

LOGICAL="${LOGICAL:-/home/yi-hack}"
SD_MNT="${SD_MNT:-/tmp/sd}"
CIFS_MNT="${CIFS_MNT:-/tmp/cifs-ro}"
CONFIG_DIR="${CONFIG_DIR:-$LOGICAL/config}"
. "$LOGICAL/base/script/get_config.sh"
. "$LOGICAL/base/script/version_compat.sh"

MODEL=$(cat /home/app/.camver 2>/dev/null)
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') apply_config: $*"; }
is_mounted() { mount 2>/dev/null | grep -q " $1 "; }

# Never overridden from the share:
#  - camera.conf / ptz_presets.conf : runtime state written by the device
#  - identity.conf / hostname        : per-camera identity - a mass push would
#                                      make cameras collide (same HA device / MQTT
#                                      client id / topic prefix / hostname)
#  - locked.conf                     : build-time locked settings (per model) - the
#                                      share must not be able to unlock/relock keys
EXCLUDE="camera.conf ptz_presets.conf identity.conf hostname locked.conf"

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

# Version handshake: apply NOTHING from a payload whose version is incompatible
# with the flash base. Keeps flash base+config ALIGNED (a misaligned config = brick).
if ! payload_compatible "${SRC%/*}"; then
    log "payload incompatible with base -> NOT applying config (keep flash aligned)"
    exit 0
fi

# Copy each file over flash, preserving the relative path (recursive), skipping the
# runtime-state/identity exclusions. Parameter expansion only (no basename/dirname applet).
( cd "$SRC" 2>/dev/null && find . -type f ) | while IFS= read -r f; do
    rel=${f#./}
    base=${rel##*/}
    case " $EXCLUDE " in *" $base "*) log "skip $rel (runtime state, never overridden)"; continue ;; esac
    dest="$CONFIG_DIR/$rel"
    mkdir -p "${dest%/*}"
    # Flash-wear: skip the copy (and the flash write) when content is already identical.
    if cmp -s "$SRC/$rel" "$dest"; then
        log "unchanged $rel"
    elif cp "$SRC/$rel" "$dest"; then
        log "override $rel"
    else
        log "FAILED $rel"
    fi
done

# Locked settings win over the share: re-stamp them after any override (the copy
# above is per-file, so a managed file may have brought a locked key along).
. "$LOGICAL/base/script/locked_conf.sh"
restore_locked_configs

exit 0
