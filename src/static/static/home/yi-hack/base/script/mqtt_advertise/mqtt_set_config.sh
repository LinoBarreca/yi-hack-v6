#!/bin/sh

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:$LD_LIBRARY_PATH"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
MOSQUITTO_SUB="/home/yi-hack/extra/bin/mosquitto_sub"

CONFIG_SET="/home/yi-hack/base/script/mqtt_advertise/mqtt_adv_config.sh"
CAMERA_CONF_FILE="/home/yi-hack/config/camera.conf"

. /home/yi-hack/base/script/get_config.sh

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
CAMERA_SETTING_TOPIC=$(get_config services.mqtt_advertise.CAMERA_SETTING_TOPIC)

while :; do
    TOPIC=$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'/+/set'
    SUBSCRIBED=$($MOSQUITTO_SUB -i $HOSTNAME -v -C 1 -h $HOST -t $TOPIC)
    CONF_UPPER=$(echo $SUBSCRIBED | awk '{print $1}' | awk -F / '{ print $(NF-1)}')
    CONF=$(echo $CONF_UPPER | awk '{ print tolower($0) }')
    VAL=$(echo $SUBSCRIBED | awk '{print $2}')

    sed -i "s/^\(${CONF_UPPER}\s*=\s*\).*$/\1${VAL}/" $CAMERA_CONF_FILE
    if [ "$CONF" == "switch_on" ]; then
        if [ "$VAL" == "no" ]; then
            ipc_cmd -t off
        else
            ipc_cmd -t on
        fi
    elif [ "$CONF" == "save_video_on_motion" ]; then
        if [ "$VAL" == "no" ]; then
            ipc_cmd -v always
        else
            ipc_cmd -v detect
        fi
    elif [ "$CONF" == "sensitivity" ]; then
        ipc_cmd -s $VAL
    elif [ "$CONF" == "ai_human_detection" ]; then
        if [ "$VAL" == "no" ]; then
            ipc_cmd -a off
        else
            ipc_cmd -a on
        fi
    elif [ "$CONF" == "sound_detection" ]; then
        if [ "$VAL" == "no" ]; then
            ipc_cmd -b off
        else
            ipc_cmd -b on
        fi
    elif [ "$CONF" == "led" ]; then
        if [ "$VAL" == "no" ]; then
            ipc_cmd -l off
        else
            ipc_cmd -l on
        fi
    elif [ "$CONF" == "ir" ]; then
        if [ "$VAL" == "no" ]; then
            ipc_cmd -i off
        else
            ipc_cmd -i on
        fi
    elif [ "$CONF" == "rotate" ]; then
        if [ "$VAL" == "no" ]; then
            ipc_cmd -r off
        else
            ipc_cmd -r on
        fi
    fi
    $CONFIG_SET
done
