#!/bin/sh

# 0.1.0 - yi-hack-v6
#
# build_view.sh - build the logical view /home/yi-hack/{extra,output} (sections 5.5, 6.6).
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
#   output = PER-CATEGORY symlinks (record/snapshot/log/swap) per the matrix (5.6),
#            from config/output.conf. NEVER-DANGLING: a link is created only after
#            verifying the target is mounted+writable; otherwise a defined fallback.
#
# Exit: 0 = extra valid (boot the payload) ; 1 = extra empty -> minimal boot.
#
# Test overrides: LOGICAL, SD_MNT, CIFS_MNT, RAM_BASE, CONFIG_DIR, CIFS_RW_MNT

LOGICAL="${LOGICAL:-/home/yi-hack}"
SD_MNT="${SD_MNT:-/tmp/sd}"
CIFS_MNT="${CIFS_MNT:-/tmp/cifs}"
RAM_BASE="${RAM_BASE:-/tmp/yi-hack}"
CONFIG_DIR="${CONFIG_DIR:-$LOGICAL/config}"
CIFS_RW_MNT="${CIFS_RW_MNT:-}"   # dedicated RW mount for output->CIFS (empty = unavailable; the CIFS payload is RO)
. "$LOGICAL/base/script/get_config.sh"
. "$LOGICAL/base/script/version_compat.sh"

MODEL=$(cat /home/app/.camver 2>/dev/null)
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') build_view: $*"; }

is_mounted() { mount 2>/dev/null | grep -q " $1 "; }
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
if [ "$(get_config cifs.ENABLED)" = "yes" ] && is_mounted "$CIFS_MNT"; then
    EXTRA_SRC=$(extra_on "$CIFS_MNT") && log "extra <- CIFS ($EXTRA_SRC)"
fi
if [ -z "$EXTRA_SRC" ] && is_mounted "$SD_MNT"; then
    EXTRA_SRC=$(extra_on "$SD_MNT") && log "extra <- SD ($EXTRA_SRC)"
fi
# Version handshake (5.8): refuse a payload whose version is incompatible with the
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
        snapshot|log) ram_link "$1"; log "fallback $1 -> RAM" ;;
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
                log "$_cat -> FLASH BLOCKED (flash wear = brick, 5.6)"; fallback "$_cat"
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

link_output record   "$(get_config output.RECORD)"
link_output snapshot "$(get_config output.SNAPSHOT)"
link_output log      "$(get_config output.LOG)"
link_output swap     "$(get_config output.SWAP)"

[ -n "$EXTRA_SRC" ] && exit 0 || exit 1
