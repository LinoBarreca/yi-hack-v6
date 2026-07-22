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
# build_view.sh - build the logical view /home/yi-hack/{extra,output}.
#
# Runs in base/flash after base/init.sh (WiFi up) and after mount_cifs.sh (if CIFS is
# configured), before the dispatcher. base/ and config/ are REAL in flash and are NOT
# touched here.
#
#   extra  = SINGLE symlink to the active payload source (input only, never mixed):
#            CIFS configured+mounted+payload -> CIFS
#            else SD if it has a payload     -> SD
#            else empty                      -> minimal boot
#
#   output = PER-CATEGORY symlinks (record/snapshot/log/swap) per the output matrix,
#            from config/output.conf. NEVER-DANGLING: a link is created only after
#            verifying the target is mounted+writable; otherwise a defined fallback.
#
# Exit: 0 = extra valid (boot the payload) ; 1 = extra empty -> minimal boot.
#
# Test overrides: LOGICAL, SD_MNT, CIFS_MNT, RAM_BASE, CONFIG_DIR, CIFS_RW_MNT

LOGICAL="${LOGICAL:-/home/yi-hack}"
SD_MNT="${SD_MNT:-/tmp/sd}"
CIFS_MNT="${CIFS_MNT:-/tmp/cifs-ro}"
RAM_BASE="${RAM_BASE:-/tmp/yi-hack}"
CONFIG_DIR="${CONFIG_DIR:-$LOGICAL/config}"
CIFS_RW_MNT="${CIFS_RW_MNT:-}"   # dedicated RW mount for output->CIFS (empty = unavailable; the CIFS payload is RO)
. "$LOGICAL/base/script/get_config.sh"
. "$LOGICAL/base/script/version_compat.sh"

MODEL=""; read MODEL < /home/app/.camver
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') build_view: $*"; }

is_mounted() { grep -q " $1 " /proc/mounts; }
writable() {
    is_mounted "$1" || return 1
    _t="$1/.wtest.$$"; (: > "$_t") 2>/dev/null && { rm -f "$_t"; return 0; }
    return 1
}

# Path of 'extra' on a mounted source: try per-model then flat. Echo path or nothing.
extra_on() {
    for _c in "$1/$MODEL/yi-hack/extra" "$1/yi-hack/$MODEL/extra" "$1/yi-hack/extra"; do
        [ -d "$_c" ] && { echo "$_c"; return 0; }
    done
    return 1
}

relink() { rm -f "$2"; ln -s "$1" "$2"; }   # rm + ln -s (busybox-compatible, no -n)

# ---------------- extra (single symlink) ----------------
rm -f "$LOGICAL/extra"
EXTRA_SRC=""
ENABLED=""; load_config cifs ENABLED
if [ "$ENABLED" = "yes" ] && is_mounted "$CIFS_MNT"; then
    EXTRA_SRC=$(extra_on "$CIFS_MNT") && log "extra <- CIFS ($EXTRA_SRC)"
fi
if [ -z "$EXTRA_SRC" ] && is_mounted "$SD_MNT"; then
    EXTRA_SRC=$(extra_on "$SD_MNT") && log "extra <- SD ($EXTRA_SRC)"
fi
# Version handshake: refuse a payload whose version is incompatible with the
# flash base (wrong-schema config / wrong-ABI binaries) -> fall back to minimal boot.
if [ -n "$EXTRA_SRC" ] && ! payload_compatible "${EXTRA_SRC%/*}"; then
    log "payload incompatible with base -> refusing payload -> minimal boot"
    EXTRA_SRC=""
fi
if [ -n "$EXTRA_SRC" ]; then
    relink "$EXTRA_SRC" "$LOGICAL/extra"
else
    log "no usable CIFS/SD payload -> extra empty -> minimal boot"
fi

# ---------------- www (single web UI path) ----------------
# Full UI from extra if the payload is present, else the flash rescue UI. Always resolves
# (base/www-min is in flash -> never dangling). The webserver always uses /home/yi-hack/www.
if [ -d "$LOGICAL/extra/www" ]; then
    relink "$LOGICAL/extra/www" "$LOGICAL/www"; log "www -> extra/www (full UI)"
else
    relink "$LOGICAL/base/www-min" "$LOGICAL/www"; log "www -> base/www-min (rescue UI)"
fi

# ---------------- output (per-category, matrix 5.6, never-dangling) ----------------
mkdir -p "$LOGICAL/output"
ram_link() { mkdir -p "$RAM_BASE/$1"; relink "$RAM_BASE/$1" "$LOGICAL/output/$1"; }
fallback() {
    case "$1" in
        log) ram_link "$1"; log "fallback $1 -> RAM" ;;
        *)            rm -f "$LOGICAL/output/$1"; log "fallback $1 -> disabled" ;;
    esac
}

link_output() {
    _cat="$1"; _dest="$2"
    rm -f "$LOGICAL/output/$_cat"
    case "$_dest" in
        NO|"") log "$_cat: NO (disabled)" ;;
        RAM)   ram_link "$_cat"; log "$_cat -> RAM" ;;
        FLASH)
            if [ "$_cat" = "record" ]; then
                log "$_cat -> FLASH BLOCKED (flash wear = brick)"; fallback "$_cat"
            else
                mkdir -p "$LOGICAL/.output-flash/$_cat"; relink "$LOGICAL/.output-flash/$_cat" "$LOGICAL/output/$_cat"; log "$_cat -> FLASH"
            fi ;;
        SD)
            if writable "$SD_MNT"; then
                mkdir -p "$SD_MNT/output/$_cat"; relink "$SD_MNT/output/$_cat" "$LOGICAL/output/$_cat"; log "$_cat -> SD"
            else
                log "$_cat: SD not mounted/writable"; fallback "$_cat"
            fi ;;
        CIFS)
            if [ -n "$CIFS_RW_MNT" ] && writable "$CIFS_RW_MNT"; then
                mkdir -p "$CIFS_RW_MNT/output/$_cat"; relink "$CIFS_RW_MNT/output/$_cat" "$LOGICAL/output/$_cat"; log "$_cat -> CIFS(RW)"
            else
                log "$_cat: CIFS RW unavailable (payload is RO)"; fallback "$_cat"
            fi ;;
        *) log "$_cat: unknown dest '$_dest'"; fallback "$_cat" ;;
    esac
}

# Service log files routed through output/log (output.LOG matrix). "Ours" are written
# straight into the view dir; "stock" Yi binaries hardcode /tmp/<name>, so we bridge
# /tmp/<name> -> view so they obey the matrix too. On NO every known file -> /dev/null
# (binaries fopen() the symlink and write into the void; rotation is size-gated so a
# /dev/null target -> size 0 -> never rotates). NB: the stock bridge only captures a
# logger that opens its file AFTER build_view (a daemon already running keeps its old fd).
LOG_FILES_OURS="wd_rtsp.log onvif_simple_server.log onvif_notify_server.log wsd_simple_server.log"
LOG_FILES_STOCK="log.txt debug_alarm.txt debug_p2p.txt debug_oss.txt log_oss.txt"

setup_log() {
    _dest="$1"; _dir="$LOGICAL/output/log"
    case "$_dest" in
        NO|"")
            rm -f "$_dir"; mkdir -p "$_dir"
            for _f in $LOG_FILES_OURS $LOG_FILES_STOCK; do relink /dev/null "$_dir/$_f"; done
            log "log: NO -> all service logs -> /dev/null" ;;
        *)
            link_output log "$_dest" ;;   # view dir -> RAM/SD/CIFS (+ fallback)
    esac
    # Bridge the stock /tmp logs into the view so they follow the same matrix.
    for _f in $LOG_FILES_STOCK; do relink "$_dir/$_f" "/tmp/$_f"; done
}

# record: the view is /home/yi-hack/output/record, seen by ftppush/clean_records/mqttv4.
# SD is special-cased to the stock mp4record path (/tmp/sd/record, SD-fixed), so the stock
# recorder and the consumers share one location. RAM/CIFS keep the matrix open for a future
# native ffmpeg recorder, which writes to the view directly (mp4record can only do SD).
setup_record() {
    _dest="$1"; _dir="$LOGICAL/output/record"
    rm -f "$_dir"
    case "$_dest" in
        SD)
            if writable "$SD_MNT"; then
                mkdir -p "$SD_MNT/record"; relink "$SD_MNT/record" "$_dir"; log "record -> SD (/tmp/sd/record)"
            else
                log "record: SD not mounted/writable -> no view"
            fi ;;
        NO|"") log "record: NO (no view)" ;;
        *)     link_output record "$_dest" ;;   # RAM/CIFS/FLASH: native recorder only (mp4record is SD-only)
    esac
}

RECORD=""; LOG=""; SWAP_FILE=""
load_config output RECORD LOG SWAP_FILE
setup_record         "$RECORD"
setup_log            "$LOG"
link_output swap     "$SWAP_FILE"

[ -n "$EXTRA_SRC" ] && exit 0 || exit 1
