#!/bin/sh

# 0.1.0

CAMERA_CONF_FILE="/home/yi-hack/config/camera.conf"

. /home/yi-hack/base/script/get_config.sh

# Config keys are de-prefixed (file is config/services/mqtt.conf); keep the
# MQTT_ prefix on the local variables to avoid clashing with the shell's own
# USER/etc. environment.
MQTT_IP=$(get_config services.mqtt.BROKER_IP)
MQTT_PORT=$(get_config services.mqtt.BROKER_PORT)
MQTT_USER=$(get_config services.mqtt.BROKER_USER)
MQTT_PASSWORD=$(get_config services.mqtt.BROKER_PASSWORD)
MQTT_PREFIX=$(get_config identity.MQTT_PREFIX)

if [ -z "$MQTT_IP" ]; then
    exit
fi
if [ -z "$MQTT_PORT" ]; then
    exit
fi

if [ ! -z "$MQTT_USER" ]; then
    MQTT_USER="-u $MQTT_USER"
fi

if [ ! -z "$MQTT_PASSWORD" ]; then
    MQTT_PASSWORD="-P $MQTT_PASSWORD"
fi

while IFS='=' read -r key val ; do
    lkey="$(echo $key | tr '[A-Z]' '[a-z]')"
    /home/yi-hack/extra/bin/mosquitto_pub -h "$MQTT_IP" -p "$MQTT_PORT" $MQTT_USER $MQTT_PASSWORD -t $MQTT_PREFIX/stat/camera/$lkey -m $val
done < "$CAMERA_CONF_FILE"
