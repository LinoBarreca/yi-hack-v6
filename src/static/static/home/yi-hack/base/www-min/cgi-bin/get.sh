#!/bin/sh
. /home/yi-hack/base/script/get_config.sh
printf "Content-type: application/json\r\n\r\n"
PV=$(cat /home/yi-hack/config/privacy 2>/dev/null); [ -z "$PV" ] && PV=off
printf '{"CIFS_ENABLED":"%s","CIFS_HOST":"%s","CIFS_SHARE":"%s","CIFS_USER":"%s","WIFI_SSID":"%s","PRIVACY":"%s"}' \
 "$(get_config cifs.ENABLED)" "$(get_config cifs.HOST)" "$(get_config cifs.SHARE)" "$(get_config cifs.USER)" \
 "$(get_config wifi.SSID 2>/dev/null)" "$PV"
