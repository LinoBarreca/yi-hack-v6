#!/bin/sh

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:$LD_LIBRARY_PATH"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
MOSQUITTO_PUB="/home/yi-hack/extra/bin/mosquitto_pub"

. /home/yi-hack/base/script/get_config.sh

HOSTNAME=$(hostname)
FW_VERSION=$(cat /home/yi-hack/extra/../version)
HOME_VERSION=$(cat /home/app/.appver)
MODEL_SUFFIX=$(cat /home/app/.camver)
if [[ $MODEL_SUFFIX == "yi_dome_1080p" ]] || [[ $MODEL_SUFFIX == "yi_cloud_dome_1080p" ]] ; then
    HARDWARE_ID=$(dd bs=1 count=4 skip=660 if=/tmp/mmap.info 2>/dev/null | cut -c1-4)
    SERIAL_NUMBER=$(dd bs=1 count=16 skip=664 if=/tmp/mmap.info 2>/dev/null | cut -c1-16)
else
    HARDWARE_ID=$(dd bs=1 count=4 skip=592 if=/tmp/mmap.info 2>/dev/null | cut -c1-4)
    SERIAL_NUMBER=$(dd bs=1 count=16 skip=596 if=/tmp/mmap.info 2>/dev/null | cut -c1-16)
fi
LOCAL_IP=$(ifconfig wlan0 | awk '/inet addr/{print substr($2,6)}')
NETMASK=$(ifconfig wlan0 | awk '/inet addr/{print substr($4,6)}')
GATEWAY=$(route -n | awk 'NR==3{print $2}')
MAC_ADDR=$(ifconfig wlan0 | awk '/HWaddr/{print substr($5,1)}')
WLAN_ESSID=$(iwconfig wlan0 | grep ESSID | cut -d\" -f2)

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
INFO_GLOBAL_TOPIC=$(get_config services.mqtt_advertise.INFO_GLOBAL_TOPIC)
INFO_GLOBAL_RETAIN=$(get_config services.mqtt_advertise.INFO_GLOBAL_RETAIN)
INFO_GLOBAL_QOS=$(get_config services.mqtt_advertise.INFO_GLOBAL_QOS)
if [ "$INFO_GLOBAL_RETAIN" == "1" ]; then
    RETAIN="-r"
else
    RETAIN=""
fi
if [ "$INFO_GLOBAL_QOS" == "0" ] || [ "$INFO_GLOBAL_QOS" == "1" ] || [ "$INFO_GLOBAL_QOS" == "2" ]; then
    QOS="-q $INFO_GLOBAL_QOS"
else
    QOS=""
fi
TOPIC=$MQTT_PREFIX/$INFO_GLOBAL_TOPIC

# MQTT Publish
CONTENT="{ "
CONTENT=$CONTENT'"hostname":"'$HOSTNAME'",'
CONTENT=$CONTENT'"fw_version":"'$FW_VERSION'",'
CONTENT=$CONTENT'"home_version":"'$HOME_VERSION'",'
CONTENT=$CONTENT'"model_suffix":"'$MODEL_SUFFIX'",'
CONTENT=$CONTENT'"hardware_id":"'$HARDWARE_ID'",'
CONTENT=$CONTENT'"serial_number":"'$SERIAL_NUMBER'",'
CONTENT=$CONTENT'"local_ip":"'$LOCAL_IP'",'
CONTENT=$CONTENT'"netmask":"'$NETMASK'",'
CONTENT=$CONTENT'"gateway":"'$GATEWAY'",'
CONTENT=$CONTENT'"mac_addr":"'$MAC_ADDR'",'
CONTENT=$CONTENT'"wlan_essid":"'$WLAN_ESSID'"'
CONTENT=$CONTENT" }"
$MOSQUITTO_PUB -i $HOSTNAME $QOS $RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
