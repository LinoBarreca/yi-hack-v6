#!/bin/sh

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
# USER/etc. environment.
MQTT_IP=$(get_config services.mqtt.BROKER_IP)
MQTT_PORT=$(get_config services.mqtt.BROKER_PORT)
MQTT_USER=$(get_config services.mqtt.BROKER_USER)
MQTT_PASSWORD=$(get_config services.mqtt.BROKER_PASSWORD)
MQTT_PREFIX=$(get_config identity.MQTT_PREFIX)

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
