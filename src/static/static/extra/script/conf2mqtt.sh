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

# 6.0.1
#
# conf2mqtt.sh <section> - publish every key of config/<section>.conf to MQTT as
# <prefix>/stat/<section>/<key>. <section> may be a nested path (e.g.
# "services/snapshot"). Called by mqtt-config when it receives a dump request
# (empty payload on <prefix>/cmnd/<section>).

SECTION="$1"
[ -z "$SECTION" ] && exit 0

. /home/yi-hack/base/script/get_config.sh

CONF_FILE="$CONFIG_DIR/$SECTION.conf"
[ -f "$CONF_FILE" ] || exit 0

# MQTT connection (keys de-prefixed; file is config/services/mqtt.conf). The
# MQTT_ prefix on the local variables avoids clashing with the shell's own
# USER/etc. environment. Batch fork-free reads (no get_config subshells).
BROKER_IP=""; BROKER_PORT=""; BROKER_USER=""; BROKER_PASSWORD=""; MQTT_PREFIX=""
load_config services.mqtt BROKER_IP BROKER_PORT BROKER_USER BROKER_PASSWORD
load_config identity MQTT_PREFIX
MQTT_IP=$BROKER_IP
MQTT_PORT=$BROKER_PORT
MQTT_USER=$BROKER_USER
MQTT_PASSWORD=$BROKER_PASSWORD

[ -z "$MQTT_IP" ] && exit 0
[ -z "$MQTT_PORT" ] && exit 0

[ -n "$MQTT_USER" ] && MQTT_USER="-u $MQTT_USER"
[ -n "$MQTT_PASSWORD" ] && MQTT_PASSWORD="-P $MQTT_PASSWORD"

while IFS='=' read -r key val ; do
    case "$key" in
        ''|\#*) continue ;;
    esac
    lkey=$(echo "$key" | tr '[A-Z]' '[a-z]')
    /home/yi-hack/extra/bin/mosquitto_pub -h "$MQTT_IP" -p "$MQTT_PORT" $MQTT_USER $MQTT_PASSWORD -t "$MQTT_PREFIX/stat/$SECTION/$lkey" -m "$val"
done < "$CONF_FILE"
