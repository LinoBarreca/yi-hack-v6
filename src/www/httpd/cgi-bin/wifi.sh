#!/bin/sh

# 6.0.1

ACTION="none"

removedoublequotes(){
  echo "$(sed 's/^"//g;s/"$//g')"
}

PARAM="${QUERY_STRING%%=*}"
VAL="${QUERY_STRING#*=}"
PWD=""
PWD2=""

if [ "$PARAM" == "action" ]; then
     ACTION=$VAL
fi

if [ $ACTION == "scan" ]; then

# Set content type header
printf "Content-type: application/json\r\n\r\n"

# Start JSON response
printf "{\"wifi\":["

# Scan for WiFi networks and extract ESSIDs
iwlist wlan0 scan | awk -F'"' '/ESSID:/{print $2}' | while read -r ESSID; do
    # Check if ESSID is not empty
    if [ -n "$ESSID" ]; then
        # Print ESSID in JSON format
        printf "\"$ESSID\","
    fi
done

# Complete JSON response and remove trailing comma
printf "\"\"]}\n"

elif [ $ACTION == "save" ]; then

    rm -f /tmp/configure_wifi.cfg

    # Body: one "KEY=url-encoded-value" per line (see set_configs.sh - jq took
    # ~12s per invocation on this CPU, so it is gone from the save path).
    urldecode() { printf '%b' "${1//%/\\x}"; }
    while IFS= read -r ROW || [ -n "$ROW" ]; do
        case "$ROW" in *=*) ;; *) continue ;; esac
        KEY=${ROW%%=*}
        VALUE=$(urldecode "${ROW#*=}")
        if [ "$KEY" == "WIFI_ESSID" ]; then
            echo "wifi_ssid=$VALUE" >> /tmp/configure_wifi.cfg
        elif [ "$KEY" == "WIFI_PASSWORD" ]; then
            PWD=$VALUE
            echo "wifi_psk=$VALUE" >> /tmp/configure_wifi.cfg
        elif [ "$KEY" == "WIFI_PASSWORD2" ]; then
            PWD2=$VALUE
        fi
    done

    if [ "$PWD" == "$PWD2" ]; then
        /home/yi-hack/base/script/configure_wifi.sh
        sleep 1
        rm -f /tmp/configure_wifi.cfg

        printf "Content-type: application/json\r\n\r\n"
        printf "{\n"
        printf "\"%s\":\"%s\"\\n" "error" "false"
        printf "}"
    else
        rm -f /tmp/configure_wifi.cfg

        printf "Content-type: application/json\r\n\r\n"
        printf "{\n"
        printf "\"%s\":\"%s\"\\n" "error" "true"
        printf "}"
    fi

fi
