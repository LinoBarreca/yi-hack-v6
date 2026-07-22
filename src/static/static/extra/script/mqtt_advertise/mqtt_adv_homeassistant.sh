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

get_network_addr() {
    LOCAL_IP=$(ifconfig $1 | awk '/inet addr/{print substr($2,6)}')
    LOCAL_MAC=""; read LOCAL_MAC < /sys/class/net/$1/address
}

get_network_addr eth0
if [ -z $LOCAL_IP ]; then
    get_network_addr wlan0
fi

# Batch fork-free config reads (see mqtt_common.sh): the old
# one-get_config-per-key style made 42 subshells x 3 forks ≈ 8s per run.
PORT=""; load_config services.httpd PORT; HTTPD_PORT=$PORT

# Sets HOSTNAME, HOST (broker/port/user words) and MQTT_PREFIX.
mqtt_load_broker

QOS=""
load_config services.mqtt QOS \
    TOPIC_BIRTH_WILL BIRTH_MSG WILL_MSG \
    TOPIC_MOTION MOTION_START_MSG MOTION_STOP_MSG \
    TOPIC_AI_HUMAN_DETECTION AI_HUMAN_DETECTION_MSG \
    TOPIC_BABY_CRYING BABY_CRYING_MSG \
    TOPIC_SOUND_DETECTION SOUND_DETECTION_MSG \
    TOPIC_MOTION_IMAGE \
    RETAIN_MOTION RETAIN_AI_HUMAN_DETECTION RETAIN_SOUND_DETECTION RETAIN_MOTION_IMAGE
MQTT_QOS=$QOS   # QOS is reused below as a JSON fragment, keep the config value

load_config services.mqtt_advertise \
    HOMEASSISTANT_MQTT_PREFIX HOMEASSISTANT_RETAIN HOMEASSISTANT_QOS \
    HOMEASSISTANT_MANUFACTURER HOMEASSISTANT_MODEL \
    INFO_GLOBAL_ENABLE INFO_GLOBAL_TOPIC INFO_GLOBAL_RETAIN INFO_GLOBAL_QOS \
    CAMERA_SETTING_ENABLE \
    TELEMETRY_ENABLE TELEMETRY_TOPIC TELEMETRY_RETAIN TELEMETRY_QOS
MANUFACTURER=$HOMEASSISTANT_MANUFACTURER
MODEL=$HOMEASSISTANT_MODEL

load_config identity HOMEASSISTANT_NAME HOMEASSISTANT_IDENTIFIERS
NAME=$HOMEASSISTANT_NAME
IDENTIFIERS=$HOMEASSISTANT_IDENTIFIERS
SW_VERSION=""; read SW_VERSION < /home/yi-hack/extra/../version
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
MQTT_RETAIN_MOTION=$RETAIN_MOTION
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
MQTT_RETAIN_AI_HUMAN_DETECTION=$RETAIN_AI_HUMAN_DETECTION
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
MQTT_RETAIN_SOUND_DETECTION=$RETAIN_SOUND_DETECTION
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
MQTT_RETAIN_MOTION_IMAGE=$RETAIN_MOTION_IMAGE
#Don't know why... ..Home Assistant don't allow retain for Sensor and Binary Sensor
# if [ "$MQTT_RETAIN_MOTION_IMAGE" == "1" ]; then
#    RETAIN='"retain":true, '
# else
    RETAIN=""
# fi
CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS', "qos": "'$MQTT_QOS'", '$RETAIN' "topic":"'$MQTT_PREFIX'/'$TOPIC_MOTION_IMAGE'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'", "platform": "mqtt"}'
$MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
# Camera-setting entities point at the mqtt-config command surface
# (cmnd/camera/<KEY>) and at the per-key state echoed by mqttv4
# (stat/camera/<key>). They require services/mqtt.conf CONFIG_ENABLED=yes.
# Commands are published non-retained: a retained cmnd would be re-executed
# by mqtt-config at every reconnection.
CAMERA_SWITCHES="
SWITCH_ON|Switch Status|mdi:video
SAVE_VIDEO_ON_MOTION|Save Video on Motion|mdi:content-save
MOTION_DETECTION|Motion Detection|mdi:motion-sensor
SOUND_DETECTION|Sound Detection|mdi:music-note
LED|Status Led|mdi:led-on
IR|IR Led|mdi:remote
MIC|Microphone|mdi:microphone
ROTATE|Rotate|mdi:monitor
AI_HUMAN_DETECTION|AI Human Detection|mdi:human
AI_VEHICLE_DETECTION|AI Vehicle Detection|mdi:car
AI_ANIMAL_DETECTION|AI Animal Detection|mdi:paw
FACE_DETECTION|Face Detection|mdi:face-recognition
MOTION_TRACKING|Motion Tracking|mdi:radar
BABY_CRYING_DETECT|Baby Crying Detect|mdi:baby-face-outline"
CAMERA_SELECTS="
SENSITIVITY|Sensitivity|mdi:tune|\"low\",\"medium\",\"high\"
SOUND_SENSITIVITY|Sound Sensitivity|mdi:tune|\"30\",\"35\",\"40\",\"45\",\"50\",\"60\",\"70\",\"80\",\"90\"
CRUISE|Cruise|mdi:rotate-3d-variant|\"no\",\"presets\",\"360\""

if [ "$CAMERA_SETTING_ENABLE" == "yes" ]; then
    echo "$CAMERA_SWITCHES" | while IFS='|' read -r KEY UNIQUE_NAME ICON; do
        [ -z "$KEY" ] && continue
        LKEY=$(echo "$KEY" | tr 'A-Z' 'a-z')
        UNIQUE_ID=$IDENTIFIERS"-"$KEY
        TOPIC=$HOMEASSISTANT_MQTT_PREFIX/switch/$IDENTIFIERS/$KEY/config
        CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS',"icon":"'$ICON'","state_topic":"'$MQTT_PREFIX'/stat/camera/'$LKEY'","command_topic":"'$MQTT_PREFIX'/cmnd/camera/'$KEY'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","payload_on":"yes","payload_off":"no", "platform": "mqtt"}'
        $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    done
    echo "$CAMERA_SELECTS" | while IFS='|' read -r KEY UNIQUE_NAME ICON OPTIONS; do
        [ -z "$KEY" ] && continue
        LKEY=$(echo "$KEY" | tr 'A-Z' 'a-z')
        UNIQUE_ID=$IDENTIFIERS"-"$KEY
        TOPIC=$HOMEASSISTANT_MQTT_PREFIX/select/$IDENTIFIERS/$KEY/config
        CONTENT='{"availability_topic":"'$MQTT_PREFIX'/'$TOPIC_BIRTH_WILL'","payload_available":"'$BIRTH_MSG'","payload_not_available":"'$WILL_MSG'","device":'$DEVICE_DETAILS',"icon":"'$ICON'","state_topic":"'$MQTT_PREFIX'/stat/camera/'$LKEY'","command_topic":"'$MQTT_PREFIX'/cmnd/camera/'$KEY'","name":"'$UNIQUE_NAME'","unique_id":"'$UNIQUE_ID'","options":['$OPTIONS'], "platform": "mqtt"}'
        $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
    done
else
    echo "$CAMERA_SWITCHES" | while IFS='|' read -r KEY UNIQUE_NAME ICON; do
        [ -z "$KEY" ] && continue
        TOPIC=$HOMEASSISTANT_MQTT_PREFIX/switch/$IDENTIFIERS/$KEY/config
        $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -n
    done
    echo "$CAMERA_SELECTS" | while IFS='|' read -r KEY UNIQUE_NAME ICON OPTIONS; do
        [ -z "$KEY" ] && continue
        TOPIC=$HOMEASSISTANT_MQTT_PREFIX/select/$IDENTIFIERS/$KEY/config
        $MOSQUITTO_PUB -i $HOSTNAME $HA_QOS $HA_RETAIN -h $HOST -t $TOPIC -n
    done
fi