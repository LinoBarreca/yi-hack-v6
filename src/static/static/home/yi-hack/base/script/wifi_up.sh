#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# wifi_up.sh - bring WiFi up BEFORE mount_cifs, decoupled from the stock 'dispatch'.
#
# WHY: on a clean v6 boot the stock 'dispatch' (which normally associates WiFi via
# wificonnect.sh) is commented out of app/init.sh and only (re)launched later, AFTER
# mount_cifs/build_view. So without this, mount_cifs runs with no network and the CIFS
# (diskless) boot always falls to minimal boot. This script associates WiFi first.
#
# SOURCE OF TRUTH = mtdblock2 (the Xiaomi 'conf' partition: SSID@28, PSK@92, both ASCII,
# NUL-padded; flag@24). The whole Xiaomi/QR/reset ecosystem uses it, so we keep it as the
# single runtime truth and NEVER wholesale-write it - only the offset-precise 28/92 (+24)
# writes that configure_wifi.sh already does (conv=notrunc preserves the Xiaomi blob at
# 156/220/476...). wifi.conf (flash, class-1, overridable from SD/CIFS via apply_config) is
# the OVERRIDE surface: if it carries an SSID we apply it to mtdblock2[28/92], so we and
# 'dispatch' agree on one set of credentials.
#
# COEXISTENCE WITH dispatch (verified by RE, stock_firmware/<m>/dispatch_re/FINDINGS.md):
# dispatch decides whether to reconnect from the LIVE `wpa_cli -i wlan0 status`, NOT from
# mtdblock2. So if we associate first using the SAME invocation as wificonnect.sh (same
# -g global ctrl socket + wlan0 ctrl iface), dispatch later sees wpa_state=COMPLETED and
# does NOT kill/reconnect -> zero bounce.

. /home/yi-hack/base/script/get_config.sh

MTD=/dev/mtdblock2
SSID_OFF=28
PSK_OFF=92
FLAG_OFF=24
FIELD_LEN=64
WPACONF=/tmp/wpa_supplicant.conf
GLOBAL=/var/run/wpa_supplicant-global
IFACE=wlan0
WAIT=45                         # seconds to wait for association + DHCP IP

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') wifi_up: $*"; }

# Read a NUL-terminated ASCII field from mtdblock2 (ash command substitution stops at NUL).
read_mtd() { dd if="$MTD" bs=1 skip="$1" count="$FIELD_LEN" 2>/dev/null; }

CUR_SSID=$(read_mtd "$SSID_OFF")
CUR_PSK=$(read_mtd "$PSK_OFF")

# --- Override: wifi.conf (flash) wins if it carries an SSID; apply to mtdblock2[28/92] ---
# Only when it actually differs (idempotent: normal boots do ZERO flash writes).
OVR_SSID=$(get_config wifi.SSID 2>/dev/null)
OVR_PSK=$(get_config wifi.PSK 2>/dev/null)

if [ -n "$OVR_SSID" ] && { [ "$OVR_SSID" != "$CUR_SSID" ] || [ "$OVR_PSK" != "$CUR_PSK" ]; }; then
    if [ "${#OVR_SSID}" -le 63 ] && [ "${#OVR_PSK}" -le 63 ]; then
        log "wifi.conf override differs -> writing mtdblock2[28/92] (offset-precise, blob preserved)"
        # clear (NUL) then write, conv=notrunc so only these fields change.
        dd if=/dev/zero of="$MTD" bs=1 seek="$SSID_OFF" count="$FIELD_LEN" conv=notrunc 2>/dev/null
        dd if=/dev/zero of="$MTD" bs=1 seek="$PSK_OFF"  count="$FIELD_LEN" conv=notrunc 2>/dev/null
        printf '%s' "$OVR_SSID" | dd of="$MTD" bs=1 seek="$SSID_OFF" conv=notrunc 2>/dev/null
        printf '%s' "$OVR_PSK"  | dd of="$MTD" bs=1 seek="$PSK_OFF"  conv=notrunc 2>/dev/null
        # clear the 'connected' flag (mark provisioned, like configure_wifi.sh)
        printf '\000\000\000\000' | dd of="$MTD" bs=1 seek="$FLAG_OFF" count=4 conv=notrunc 2>/dev/null
        sync
        CUR_SSID=$OVR_SSID
        CUR_PSK=$OVR_PSK
    else
        log "wifi.conf override ignored (SSID/PSK longer than 63 chars)"
    fi
fi

SSID=$CUR_SSID
PSK=$CUR_PSK

if [ -z "$SSID" ]; then
    log "no WiFi credentials (mtdblock2 + wifi.conf empty) -> leaving WiFi to stock QR/dispatch"
    exit 1
fi

ifconfig "$IFACE" up 2>/dev/null

# --- Associate (skip if already associated, e.g. dispatch or a prior run) ---
if wpa_cli -i "$IFACE" status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
    log "$IFACE already associated (wpa_state=COMPLETED); ensuring DHCP"
else
    # Generate /tmp/wpa_supplicant.conf one-way. wpa_passphrase hashes WPA-PSK keys (8..63);
    # otherwise treat as open network. ctrl_interface matches the stock global socket layout.
    {
        echo "ctrl_interface=/var/run/wpa_supplicant"
        echo "update_config=1"
        if [ -n "$PSK" ] && [ "${#PSK}" -ge 8 ] && [ "${#PSK}" -le 63 ]; then
            wpa_passphrase "$SSID" "$PSK" | grep -v '^[[:space:]]*#'
        elif [ -n "$PSK" ]; then
            printf 'network={\n\tssid="%s"\n\tpsk="%s"\n}\n' "$SSID" "$PSK"
        else
            printf 'network={\n\tssid="%s"\n\tkey_mgmt=NONE\n}\n' "$SSID"
        fi
    } > "$WPACONF"
    chmod 600 "$WPACONF"

    # Same invocation as the stock wificonnect.sh (WEXT default driver, shared global socket).
    # Don't stack instances.
    if ! pidof wpa_supplicant >/dev/null 2>&1; then
        log "launching wpa_supplicant on $IFACE (SSID set, ${#PSK}-char key)"
        wpa_supplicant -c"$WPACONF" -g"$GLOBAL" -i"$IFACE" -B 2>/dev/null
    fi
fi

# --- DHCP (reuse the stock hook) + wait for an IP ---
/home/yi-hack/base/script/wifidhcp.sh

i=0
while [ "$i" -lt "$WAIT" ]; do
    if ifconfig "$IFACE" 2>/dev/null | grep -q "inet addr:"; then
        log "$IFACE up with IP after ${i}s"
        exit 0
    fi
    i=$((i + 1))
    sleep 1
done

log "timeout (${WAIT}s) waiting for IP on $IFACE -> continuing (mount_cifs will retry/fallback)"
exit 1
