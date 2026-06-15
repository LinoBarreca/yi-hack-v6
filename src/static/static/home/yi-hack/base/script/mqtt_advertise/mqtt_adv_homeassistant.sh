#!/bin/sh

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:$LD_LIBRARY_PATH"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
MOSQUITTO_PUB="/home/yi-hack/extra/bin/mosquitto_pub"

. /home/yi-hack/base/script/get_config.sh

get_network_addr() {
    LOCAL_IP=$(ifconfig $1 | awk '/inet addr/{print substr($2,6)}')
    LOCAL_MAC=$(cat /sys/class/net/$1/address)
}

get_network_addr eth0
if [ -z $LOCAL_IP ]; then
    get_network_addr wlan0
fi

HTTPD_PORT=$(get_config system.HTTPD_PORT)
HOSTNAME=$(hostname)
MQTT_IP=$(get_config services.mqtt.BROKER_IP)
MQTT_PORT=$(get_config services.mqtt.BROKER_PORT)
MQTT_USER=$(get_config services.mqtt.BROKER_USER)
MQTT_PASSWORD=$(get_config services.mqtt.BROKER_PASSWORD)
MQTT_QOS=$(get_config services.mqtt.QOS)

TOPIC_BIRTH_WILL=$(get_config services.mqtt.TOPIC_BIRTH_WILL)
BIRTH_MSG=$(get_config services.mqtt.BIRTH_MSG)
WILL_MSG=$(get_config services.mqtt.WILL_MSG)

TOPIC_MOTION=$(get_config services.mqtt.TOPIC_MOTION)
MOTION_START_MSG=$(get_config services.mqtt.MOTION_START_MSG)
MOTION_STOP_MSG=$(get_config services.mqtt.MOTION_STOP_MSG)

TOPIC_AI_HUMAN_DETECTION=$(get_config services.mqtt.TOPIC_AI_HUMAN_DETECTION)
AI_HUMAN_DETECTION_MSG=$(get_config services.mqtt.AI_HUMAN_DETECTION_MSG)

TOPIC_BABY_CRYING=$(get_config services.mqtt.TOPIC_BABY_CRYING)
BABY_CRYING_MSG=$(get_config services.mqtt.BABY_CRYING_MSG)

TOPIC_SOUND_DETECTION=$(get_config services.mqtt.TOPIC_SOUND_DETECTION)
SOUND_DETECTION_MSG=$(get_config services.mqtt.SOUND_DETECTION_MSG)

TOPIC_MOTION_IMAGE=$(get_config services.mqtt.TOPIC_MOTION_IMAGE)

HOST=$MQTT_IP
if [ ! -z $MQTT_PORT ]; then
    HOST=$HOST' -p '$MQTT_PORT
fi
if [ ! -z $MQTT_USER ]; then
    HOST=$HOST' -u '$MQTT_USER' -P '$MQTT_PASSWORD
fi

MQTT_PREFIX=$(get_config identity.MQTT_PREFIX)

HOMEASSISTANT_MQTT_PREFIX=$(get_config services.mqtt_advertise.HOMEASSISTANT_MQTT_PREFIX)
HOMEASSISTANT_RETAIN=$(get_config services.mqtt_advertise.HOMEASSISTANT_RETAIN)
HOMEASSISTANT_QOS=$(get_config services.mqtt_advertise.HOMEASSISTANT_QOS)
INFO_GLOBAL_ENABLE=$(get_config services.mqtt_advertise.INFO_GLOBAL_ENABLE)
INFO_GLOBAL_TOPIC=$(get_config services.mqtt_advertise.INFO_GLOBAL_TOPIC)
INFO_GLOBAL_RETAIN=$(get_config services.mqtt_advertise.INFO_GLOBAL_RETAIN)
INFO_GLOBAL_QOS=$(get_config services.mqtt_advertise.INFO_GLOBAL_QOS)
CAMERA_SETTING_ENABLE=$(get_config services.mqtt_advertise.CAMERA_SETTING_ENABLE)
CAMERA_SETTING_TOPIC=$(get_config services.mqtt_advertise.CAMERA_SETTING_TOPIC)
CAMERA_SETTING_RETAIN=$(get_config services.mqtt_advertise.CAMERA_SETTING_RETAIN)
CAMERA_SETTING_QOS=$(get_config services.mqtt_advertise.CAMERA_SETTING_QOS)
TELEMETRY_ENABLE=$(get_config services.mqtt_advertise.TELEMETRY_ENABLE)
TELEMETRY_TOPIC=$(get_config services.mqtt_advertise.TELEMETRY_TOPIC)
TELEMETRY_RETAIN=$(get_config services.mqtt_advertise.TELEMETRY_RETAIN)
TELEMETRY_QOS=$(get_config services.mqtt_advertise.TELEMETRY_QOS)
NAME=$(get_config identity.HOMEASSISTANT_NAME)
IDENTIFIERS=$(get_config identity.HOMEASSISTANT_IDENTIFIERS)
MANUFACTURER=$(get_config services.mqtt_advertise.HOMEASSISTANT_MANUFACTURER)
MODEL=$(get_config services.mqtt_advertise.HOMEASSISTANT_MODEL)
SW_VERSION=$(cat /home/yi-hack/extra/../version)
DEVICE_DETAILS="{\"identifiers\":[\"$IDENTIFIERS\"],\"connections\":[[\"mac\",\"${LOCAL_MAC}\"]],\"manufacturer\":\"$MANUFACTURER\",\"model\":\"$MODEL\",\"name\":\"$NAME\",\"sw_version\":\"$SW_VERSION\",\"configuration_url\":\"http://$LOCAL_IP:$HTTPD_PORT\"}"

if [ "$HOMEASSISTANT_RETAIN" == "1" ]; then
    HA_RETAIN="-r"
else
    HA_RETAIN=""
fi
if [ "$HOMEASSISTANT_QOS" == "0" ] || [ "$HOMEASSISTANT_QOS" == "1" ] || [ "$HOMEASSISTANT_QOS" == "2" ]; then
    HA_QOS="-q $HOMEASSISTANT_QOS"
else
    HA_QOS=""
fi

if [ "$INFO_GLOBAL_ENABLE" == "yes" ]; then
    #Don't know why... ..Home Assistant don't allow retain for Sensor and Binary Sensor
    ## if [ "$INFO_GLOBAL_RETAIN" == "1" ]; then
    ##    RETAIN='"retain":true, '
    ## else
        RETAIN=""
    ## fi
    if [ "$INFO_GLOBAL_QOS" == "1" ] || [ "$INFO_GLOBAL_QOS" == "2" ]; then
        QOS='"qos":'$INFO_GLOBAL_QOS', '
    else
        QOS=""
    fi
    #Hostname
    UNIQUE_NAME="Hostname"
    UNIQUE_ID=$IDENTIFIERS"-hostname"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/hostname/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:network","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.hostname }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #IP
    UNIQUE_NAME="Local IP"
    UNIQUE_ID=$IDENTIFIERS"-local_ip"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/local_ip/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:ip","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.local_ip }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Netmask
    UNIQUE_NAME="Netmask"
    UNIQUE_ID=$IDENTIFIERS"-netmask"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/netmask/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:ip","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.netmask }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Gateway
    UNIQUE_NAME="Gateway"
    UNIQUE_ID=$IDENTIFIERS"-gateway"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/gateway/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:ip","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.gateway }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #WLan ESSID
    UNIQUE_NAME="WiFi ESSID"
    UNIQUE_ID=$IDENTIFIERS"-wlan_essid"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/wlan_essid/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:wifi","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.wlan_essid }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Mac Address
    UNIQUE_NAME="Mac Address"
    UNIQUE_ID=$IDENTIFIERS"-mac_addr"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/mac_addr/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:network","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.mac_addr }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Home Version
    UNIQUE_NAME="Home Version"
    UNIQUE_ID=$IDENTIFIERS"-home_version"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/home_version/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:memory","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.home_version }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Firmware Version
    UNIQUE_NAME="Firmware Version"
    UNIQUE_ID=$IDENTIFIERS"-fw_version"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/fw_version/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:network","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.fw_version }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Model Suffix
    UNIQUE_NAME="Model Suffix"
    UNIQUE_ID=$IDENTIFIERS"-model_suffix"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/model_suffix/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:network","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.model_suffix }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Serial Number
    UNIQUE_NAME="Serial Number"
    UNIQUE_ID=$IDENTIFIERS"-serial_number"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/serial_number/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:webcam","state_topic":"'$MQTT_PREFIX'/'$INFO_GLOBAL_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.serial_number }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
else
    for ITEM in hostname local_ip netmask gateway wlan_essid mac_addr home_version fw_version model_suffix serial_number; do
        TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/$ITEM/config
        $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -n
    done
fi
if [ "$TELEMETRY_ENABLE" == "yes" ]; then
    #Don't know why... ..Home Assistant don't allow retain for Sensor and Binary Sensor
    ## if [ "$TELEMETRY_RETAIN" == "1" ]; then
    ##    RETAIN='"retain":true, '
    ## else
        RETAIN=""
    ## fi
    if [ "$TELEMETRY_QOS" == "1" ] || [ "$TELEMETRY_QOS" == "2" ]; then
        QOS='"qos":'$TELEMETRY_QOS', '
    else
        QOS=""
    fi
    #Total Memory
    UNIQUE_NAME="Total Memory"
    UNIQUE_ID=$IDENTIFIERS"-total_memory"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/total_memory/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:memory","state_topic":"'$MQTT_PREFIX'/'$TELEMETRY_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.total_memory }}","unit_of_measurement":"KB", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Free Memory
    UNIQUE_NAME="Free Memory"
    UNIQUE_ID=$IDENTIFIERS"-free_memory"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/free_memory/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:memory","state_topic":"'$MQTT_PREFIX'/'$TELEMETRY_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.free_memory }}","unit_of_measurement":"KB", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #FreeSD
    UNIQUE_NAME="Free SD"
    UNIQUE_ID=$IDENTIFIERS"-free_sd"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/free_sd/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:micro-sd","state_topic":"'$MQTT_PREFIX'/'$TELEMETRY_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.free_sd|regex_replace(find=\"%\", replace=\"\", ignorecase=False) }}","unit_of_measurement":"%", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Load AVG
    UNIQUE_NAME="Load AVG"
    UNIQUE_ID=$IDENTIFIERS"-load_avg"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/load_avg/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:network","state_topic":"'$MQTT_PREFIX'/'$TELEMETRY_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.load_avg }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #Uptime
    UNIQUE_NAME="Uptime"
    UNIQUE_ID=$IDENTIFIERS"-uptime"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/uptime/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "device_class":"timestamp","icon":"mdi:timer-outline","state_topic":"'$MQTT_PREFIX'/'$TELEMETRY_TOPIC'","name":"'$UNIQUE_NAME'","'unique_id'":"'$UNIQUE_ID'","value_template":"{{ (as_timestamp(now())-(value_json.uptime|int))|timestamp_local }}", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    #WLanStrenght
    UNIQUE_NAME="Wlan Strengh"
    UNIQUE_ID=$IDENTIFIERS"-wlan_strength"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/wlan_strength/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "device_class":"signal_strength","icon":"mdi:wifi","state_topic":"'$MQTT_PREFIX'/'$TELEMETRY_TOPIC'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ ((value_json.wlan_strength|int) * 100 / 70 )|int }}","unit_of_measurement":"%", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
else
    for ITEM in total_memory free_memory free_sd load_avg uptime wlan_strength; do
        TOPIC=$HOMEASSISTANT_MQTT_PREFIX/sensor/$IDENTIFIERS/$ITEM/config
        $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -n
    done
fi

# Motion Detection
UNIQUE_NAME="Movement"
UNIQUE_ID=$IDENTIFIERS"-motion_detection"
TOPIC=$HOMEASSISTANT_MQTT_PREFIX/binary_sensor/$IDENTIFIERS/motion_detection/config
MQTT_RETAIN_MOTION=$(get_config services.mqtt.RETAIN_MOTION)
#Don't know why... ..Home Assistant don't allow retain for Sensor and Binary Sensor
# if [ "$MQTT_RETAIN_MOTION" == "1" ]; then
#    RETAIN='"retain":true, '
# else
    RETAIN=""
# fi
CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS', "qos": "'$MQTT_QOS'", '$RETAIN' "device_class":"motion","state_topic":"'$MQTT_PREFIX'/'$TOPIC_MOTION'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","payload_on":"'$MOTION_START_MSG'","payload_off":"'$MOTION_STOP_MSG'", "platform": "mqtt"}'
$MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
# Human Detection
UNIQUE_NAME="Human Detection"
UNIQUE_ID=$IDENTIFIERS"-ai_human_detection"
TOPIC=$HOMEASSISTANT_MQTT_PREFIX/binary_sensor/$IDENTIFIERS/ai_human_detection/config
MQTT_RETAIN_AI_HUMAN_DETECTION=$(get_config services.mqtt.RETAIN_AI_HUMAN_DETECTION)
#Don't know why... ..Home Assistant don't allow retain for Sensor and Binary Sensor
# if [ "$MQTT_RETAIN_AI_HUMAN_DETECTION" == "1" ]; then
#    RETAIN='"retain":true, '
# else
    RETAIN=""
# fi
CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS', "qos": "'$MQTT_QOS'", '$RETAIN' "device_class":"motion","state_topic":"'$MQTT_PREFIX'/'$TOPIC_AI_HUMAN_DETECTION'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","payload_on":"'$AI_HUMAN_DETECTION_MSG'","off_delay":60, "platform": "mqtt"}'
$MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
# Sound Detection
UNIQUE_NAME="Sound Detection"
UNIQUE_ID=$IDENTIFIERS"-sound_detection"
TOPIC=$HOMEASSISTANT_MQTT_PREFIX/binary_sensor/$IDENTIFIERS/sound_detection/config
MQTT_RETAIN_SOUND_DETECTION=$(get_config services.mqtt.RETAIN_SOUND_DETECTION)
#Don't know why... ..Home Assistant don't allow retain for Sensor and Binary Sensor
# if [ "$MQTT_RETAIN_SOUND_DETECTION" == "1" ]; then
#    RETAIN='"retain":true, '
# else
    RETAIN=""
# fi
CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS', "qos": "'$MQTT_QOS'", '$RETAIN' "device_class":"sound","state_topic":"'$MQTT_PREFIX'/'$TOPIC_SOUND_DETECTION'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","payload_on":"'$SOUND_DETECTION_MSG'","off_delay":60, "platform": "mqtt"}'
$MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
# try to remove baby_crying topic
TOPIC=$HOMEASSISTANT_MQTT_PREFIX/binary_sensor/$IDENTIFIERS/baby_crying/config
$MOSQUITTO_PUB -i $HOSTNAME -h $HOST -t $TOPIC -m ""
# Motion Detection Image
UNIQUE_NAME="Motion Detection Image"
UNIQUE_ID=$IDENTIFIERS"-motion_detection_image"
TOPIC=$HOMEASSISTANT_MQTT_PREFIX/camera/$IDENTIFIERS/motion_detection_image/config
MQTT_RETAIN_MOTION_IMAGE=$(get_config services.mqtt.RETAIN_MOTION_IMAGE)
#Don't know why... ..Home Assistant don't allow retain for Sensor and Binary Sensor
# if [ "$MQTT_RETAIN_MOTION_IMAGE" == "1" ]; then
#    RETAIN='"retain":true, '
# else
    RETAIN=""
# fi
CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS', "qos": "'$MQTT_QOS'", '$RETAIN' "topic":"'$MQTT_PREFIX'/'$TOPIC_MOTION_IMAGE'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'", "platform": "mqtt"}'
$MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
if [ "$CAMERA_SETTING_ENABLE" == "yes" ]; then
    if [ "$CAMERA_SETTING_RETAIN" == "1" ]; then
        RETAIN='"retain":true, '
    else
        RETAIN=""
    fi
    if [ "$CAMERA_SETTING_QOS" == "1" ] || [ "$CAMERA_SETTING_QOS" == "2" ]; then
        QOS='"qos":'$CAMERA_SETTING_QOS', '
    else
        QOS=""
    fi
    # Switch On
    UNIQUE_NAME="Switch Status"
    UNIQUE_ID=$IDENTIFIERS"-SWITCH_ON"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/switch/$IDENTIFIERS/SWITCH_ON/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:video","state_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'","command_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'/SWITCH_ON/set","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.SWITCH_ON }}","payload_on":"yes","payload_off":"no", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    # Sound Detection
    UNIQUE_NAME="Sound Detection"
    UNIQUE_ID=$IDENTIFIERS"-SOUND_DETECTION"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/switch/$IDENTIFIERS/SOUND_DETECTION/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS', '$QOS' '$RETAIN' "icon":"mdi:music-note","state_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'","command_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'/SOUND_DETECTION/set","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.SOUND_DETECTION }}","payload_on":"yes","payload_off":"no", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    # try to remove baby_crying topic
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/switch/$IDENTIFIERS/BABY_CRYING_DETECT/config
    $MOSQUITTO_PUB -i $HOSTNAME -h $HOST -t $TOPIC -n
    # Led
    UNIQUE_NAME="Status Led"
    UNIQUE_ID=$IDENTIFIERS"-LED"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/switch/$IDENTIFIERS/LED/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:led-on","state_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'","command_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'/LED/set","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.LED }}","payload_on":"yes","payload_off":"no", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    # IR
    UNIQUE_NAME="IR Led"
    UNIQUE_ID=$IDENTIFIERS"-IR"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/switch/$IDENTIFIERS/IR/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:remote","state_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'","command_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'/IR/set","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.IR }}","payload_on":"yes","payload_off":"no", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    # Rotate
    UNIQUE_NAME="Rotate"
    UNIQUE_ID=$IDENTIFIERS"-ROTATE"
    TOPIC=$HOMEASSISTANT_MQTT_PREFIX/switch/$IDENTIFIERS/ROTATE/config
    CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS','$QOS' '$RETAIN' "icon":"mdi:monitor","state_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'","command_topic":"'$MQTT_PREFIX'/'$CAMERA_SETTING_TOPIC'/ROTATE/set","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","value_template":"{{ value_json.ROTATE }}","payload_on":"yes","payload_off":"no", "platform": "mqtt"}'
    $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
else
    for ITEM in SWITCH_ON SOUND_DETECTION BABY_CRYING_DETECT LED IR ROTATE; do
        TOPIC=$HOMEASSISTANT_MQTT_PREFIX/switch/$IDENTIFIERS/$ITEM/config
        $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -n
    done
fi