#!/bin/sh

# 0.1.0 - yi-hack-v6
#
# Fill per-camera identity defaults for any value left blank. Runs at boot AFTER
# apply_config + check_conf(extra) and BEFORE `hostname -F` and the MQTT daemons,
# so every consumer - shell (advertise, hostname) AND the mqttv4 / mqtt-config C
# daemons that read the .conf files directly - sees a resolved value. Idempotent:
# a non-empty value is never touched, so user overrides persist and a cleared
# field auto-heals on the next boot. Flash is written only when a field is empty
# (first boot), so no per-boot flash wear.
#
# Identity base = the factory serial (HW_ID+serial, the value on the camera's
# sticker), read straight from the vendor flash partition vd1 (mtd6, offset 36,
# 20 bytes) - present from the first instruction, no dependency on the stock
# `dispatch` dump. Fallbacks: /tmp/mmap.info @592 (stock convention), then the MAC.
#
# Logs (with timestamp) to stdout, i.e. the boot log, so a wrong/fallback source
# or an unexpected value is easy to spot when troubleshooting.

CONFIG_DIR="${CONFIG_DIR:-/home/yi-hack/config}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') set_defaults: $*"; }

# --- serial (identity base), remembering which source answered ---
SERIAL=""
SERIAL_SRC=""
_try() {   # _try <raw-value> <source-label> : accept if sane (alnum, >= 8 chars)
    _v=$(echo "$1" | tr -d '\000')
    case "$_v" in [0-9A-Za-z]*) [ ${#_v} -ge 8 ] && { SERIAL="$_v"; SERIAL_SRC="$2"; return 0; } ;; esac
    return 1
}
resolve_serial() {
    _try "$(dd if=/dev/mtdblock6 bs=1 skip=36 count=20 2>/dev/null)" "mtd6(vd1)@36"  && return
    _try "$(dd if=/tmp/mmap.info  bs=1 skip=592 count=20 2>/dev/null)" "mmap.info@592" && return
    for _i in eth0 wlan0; do
        [ -f "/sys/class/net/$_i/address" ] && \
            _try "$(tr -d ':' < "/sys/class/net/$_i/address")" "mac($_i)" && return
    done
    SERIAL="unknown"; SERIAL_SRC="FALLBACK-none"
    log "WARNING: no serial source found (mtd6/mmap.info/MAC all failed) -> using '$SERIAL'"
}

# fill_if_empty <conf_file> <KEY> <value> : set KEY only when its value is empty.
fill_if_empty() {
    _f="$1"; _k="$2"; _v="$3"
    [ -f "$_f" ] || { log "WARNING: $_f missing, cannot set $_k"; return 0; }
    _cur=$(grep -E "^${_k}=" "$_f" | cut -d= -f2- | head -n1)
    [ -n "$_cur" ] && return 0                       # already set -> keep, quietly
    if grep -qE "^${_k}=" "$_f"; then
        sed -i "s|^${_k}=.*|${_k}=${_v}|" "$_f"      # replace empty value
    else
        echo "${_k}=${_v}" >> "$_f"                  # add missing key
    fi
    log "$(basename "$_f"):$_k <- $_v"
}

resolve_serial
log "identity base = $SERIAL (source: $SERIAL_SRC)"

# --- hostname: config value > DHCP-provided > serial ---
# wifi_up/udhcpc already ran; if the DHCP server offered a hostname, default.script
# applied it live. Persist the effective value so the following `hostname -F <file>`
# uses it instead of resetting the host to an empty name.
HN_FILE="$CONFIG_DIR/hostname"
if [ ! -s "$HN_FILE" ]; then
    _cur=$(hostname 2>/dev/null)
    case "$_cur" in ""|"(none)"|localhost) _cur="" ;; esac
    if [ -n "$_cur" ]; then
        echo "$_cur" > "$HN_FILE";   log "hostname <- $_cur (from dhcp)"
    else
        echo "$SERIAL" > "$HN_FILE"; log "hostname <- $SERIAL (from serial)"
    fi
fi

# --- MQTT / Home Assistant identity: serial when blank ---
ID_FILE="$CONFIG_DIR/identity.conf"
fill_if_empty "$ID_FILE" MQTT_CLIENT_ID            "$SERIAL"
fill_if_empty "$ID_FILE" MQTT_PREFIX               "$SERIAL"
fill_if_empty "$ID_FILE" HOMEASSISTANT_IDENTIFIERS "$SERIAL"
fill_if_empty "$ID_FILE" HOMEASSISTANT_NAME        "Yi Camera $SERIAL"
