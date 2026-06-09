#!/bin/sh
. /home/yi-hack/base/www-min/cgi-bin/rescue_lib.sh
read_body
printf "Content-type: application/json\r\n\r\n"
setkey cifs.conf ENABLED "$(get_field cifs_enabled)"
setkey cifs.conf HOST    "$(get_field cifs_host)"
setkey cifs.conf SHARE   "$(get_field cifs_share)"
setkey cifs.conf USER    "$(get_field cifs_user)"
S=$(get_field wifi_ssid); P=$(get_field wifi_psk)
[ -n "$S" ] && setkey wifi.conf SSID "$S"
[ -n "$P" ] && setkey wifi.conf PSK "$P"
# NOTE: applying WiFi to the radio (wifi.conf -> wpa_supplicant) is pending.
if [ "$(get_field privacy)" = "on" ]; then echo on > "$CONFIG/privacy"; else rm -f "$CONFIG/privacy"; fi
sync
printf '{"error":"false"}'
