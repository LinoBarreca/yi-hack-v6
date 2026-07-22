#!/bin/sh

#
#  This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
#  Copyright (c) 2021-2023 alienatedsec - v5 specific
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

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:$LD_LIBRARY_PATH"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
MOSQUITTO_PUB="/home/yi-hack/extra/bin/mosquitto_pub"

. /home/yi-hack/base/script/get_config.sh
. /home/yi-hack/extra/script/mqtt_advertise/mqtt_common.sh

# /proc values with builtins (this runs from crontab; no cut/free forks).
read UPTIME _ < /proc/uptime
read _load1 _load5 _load15 _ < /proc/loadavg
LOAD_AVG="$_load1 $_load5 $_load15"
# Same numbers `free -k` shows (it reads /proc/meminfo): free = MemFree+Buffers+Cached.
TOTAL_MEMORY=0; FREE_MEMORY=0
while read -r _key _val _; do
    case "$_key" in
        MemTotal:)                 TOTAL_MEMORY=$_val ;;
        MemFree:|Buffers:|Cached:) FREE_MEMORY=$((FREE_MEMORY+_val)) ;;
    esac
done < /proc/meminfo
# sub(), NOT gsub(): busybox awk gsub() spins forever on this build (verified on camera)
FREE_SD=$(df /tmp/sd/ | awk '/mmc/{sub(/%/,"",$5); print $5}')
WLAN_STRENGTH=$(awk 'END { sub(/\.$/,"",$3); print $3 }' /proc/net/wireless)

# MQTT configuration (batch fork-free reads; see mqtt_common.sh)

mqtt_load_broker
TELEMETRY_TOPIC=""; TELEMETRY_RETAIN=""; TELEMETRY_QOS=""
load_config services.mqtt_advertise TELEMETRY_TOPIC TELEMETRY_RETAIN TELEMETRY_QOS
mqtt_flags "$TELEMETRY_RETAIN" "$TELEMETRY_QOS"
TOPIC=$MQTT_PREFIX/$TELEMETRY_TOPIC

# MQTT Publish
CONTENT="{ "
CONTENT=$CONTENT'"uptime":"'$UPTIME'",'
CONTENT=$CONTENT'"load_avg":"'$LOAD_AVG'",'
if [ ! -z "$FREE_SD" ]; then
    FREE_SD=$((100 - $FREE_SD))%
    CONTENT=$CONTENT'"free_sd":"'$FREE_SD'",'
fi
CONTENT=$CONTENT'"total_memory":"'$TOTAL_MEMORY'",'
CONTENT=$CONTENT'"free_memory":"'$FREE_MEMORY'",'
CONTENT=$CONTENT'"wlan_strength":"'$WLAN_STRENGTH'"'
CONTENT=$CONTENT" }"
$MOSQUITTO_PUB -i $HOSTNAME $QOS $RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
