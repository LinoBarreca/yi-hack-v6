#!/bin/sh

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:$LD_LIBRARY_PATH"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
MOSQUITTO_PUB="/home/yi-hack/extra/bin/mosquitto_pub"

. /home/yi-hack/base/script/get_config.sh

CONTENT=$(/home/yi-hack/www/cgi-bin/links.sh | sed 1d | sed ':a;N;$!ba;s/\n//g')

HOSTNAME=$(hostname)
MQTT_IP=$(get_config services.mqtt.BROKER_IP)
MQTT_PORT=$(get_config services.mqtt.BROKER_PORT)
MQTT_USER=$(get_config services.mqtt.BROKER_USER)
MQTT_PASSWORD=$(get_config services.mqtt.BROKER_PASSWORD)

HOST=$MQTT_IP
if [ ! -z $MQTT_PORT ]; then
    HOST=$HOST' -p '$MQTT_PORT
fi
if [ ! -z $MQTT_USER ]; then
    HOST=$HOST' -u '$MQTT_USER' -P '$MQTT_PASSWORD
fi

MQTT_PREFIX=$(get_config identity.MQTT_PREFIX)
LINK_TOPIC=$(get_config services.mqtt_advertise.LINK_TOPIC)
LINK_RETAIN=$(get_config services.mqtt_advertise.LINK_RETAIN)
LINK_QOS=$(get_config services.mqtt_advertise.LINK_QOS)
if [ "$LINK_RETAIN" == "1" ]; then
    RETAIN="-r"
else
    RETAIN=""
fi
if [ "$LINK_QOS" == "0" ] || [ "$LINK_QOS" == "1" ] || [ "$LINK_QOS" == "2" ]; then
    QOS="-q $LINK_QOS"
else
    QOS=""
fi
TOPIC=$MQTT_PREFIX/$LINK_TOPIC

$MOSQUITTO_PUB -i $HOSTNAME $QOS $RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
