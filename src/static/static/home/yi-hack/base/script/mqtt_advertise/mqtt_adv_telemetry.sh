#!/bin/sh

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:$LD_LIBRARY_PATH"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
MOSQUITTO_PUB="/home/yi-hack/extra/bin/mosquitto_pub"

. /home/yi-hack/base/script/get_config.sh

HOSTNAME=$(hostname)
UPTIME=$(cat /proc/uptime | cut -d ' ' -f1)
LOAD_AVG=$(cat /proc/loadavg | cut -d ' ' -f1-3)
TOTAL_MEMORY=$(free -k | awk 'NR==2{print $2}')
FREE_MEMORY=$(free -k | awk 'NR==2{print $4+$6+$7}')
FREE_SD=$(df /tmp/sd/ | grep mmc | awk '{print $5}' | tr -d '%')
WLAN_STRENGTH=$(cat /proc/net/wireless | awk 'END { print $3 }' | sed 's/\.$//')

# MQTT configuration

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
TELEMETRY_TOPIC=$(get_config services.mqtt_advertise.TELEMETRY_TOPIC)
TELEMETRY_RETAIN=$(get_config services.mqtt_advertise.TELEMETRY_RETAIN)
TELEMETRY_QOS=$(get_config services.mqtt_advertise.TELEMETRY_QOS)
if [ "$TELEMETRY_RETAIN" == "1" ]; then
    RETAIN="-r"
else
    RETAIN=""
fi
if [ "$TELEMETRY_QOS" == "0" ] || [ "$TELEMETRY_QOS" == "1" ] || [ "$TELEMETRY_QOS" == "2" ]; then
    QOS="-q $TELEMETRY_QOS"
else
    QOS=""
fi
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
