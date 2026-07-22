#!/bin/sh

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:$LD_LIBRARY_PATH"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
MOSQUITTO_PUB="/home/yi-hack/extra/bin/mosquitto_pub"

. /home/yi-hack/base/script/get_config.sh
. /home/yi-hack/extra/script/mqtt_advertise/mqtt_common.sh

read FW_VERSION < /home/yi-hack/extra/../version
read HOME_VERSION < /home/app/.appver
read MODEL_SUFFIX < /home/app/.camver
load_hw_ids "$MODEL_SUFFIX"
HARDWARE_ID="$HW_ID"
LOCAL_IP=$(ifconfig wlan0 | awk '/inet addr/{print substr($2,6)}')
NETMASK=$(ifconfig wlan0 | awk '/inet addr/{print substr($4,6)}')
GATEWAY=$(route -n | awk 'NR==3{print $2}')
MAC_ADDR=$(ifconfig wlan0 | awk '/HWaddr/{print substr($5,1)}')
WLAN_ESSID=$(iwconfig wlan0 | awk -F\" '/ESSID/{print $2}')

# MQTT configuration (batch fork-free reads; see mqtt_common.sh)

mqtt_load_broker
INFO_GLOBAL_TOPIC=""; INFO_GLOBAL_RETAIN=""; INFO_GLOBAL_QOS=""
load_config services.mqtt_advertise INFO_GLOBAL_TOPIC INFO_GLOBAL_RETAIN INFO_GLOBAL_QOS
mqtt_flags "$INFO_GLOBAL_RETAIN" "$INFO_GLOBAL_QOS"
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
