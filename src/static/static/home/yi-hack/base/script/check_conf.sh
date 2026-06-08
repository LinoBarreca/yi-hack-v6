#!/bin/sh

# 0.1.0 - yi-hack-v6
#
# check_conf.sh - seed default values into the flash config files. For each file,
# any default key that is MISSING is appended; existing keys are left untouched
# (so user/runtime values survive). Runs once at boot from system.sh.
#
# Layout below is kept in the SAME ORDER everywhere — file path, its defaults
# (PARMS_<FILE>), and the seeding call — so it is obvious which defaults go where.

# -----------------------------------------------------------------------------
# Config files
# -----------------------------------------------------------------------------
SYSTEM_CONF_FILE="/home/yi-hack/config/system.conf"
CAMERA_CONF_FILE="/home/yi-hack/config/camera.conf"
MQTT_CONF_FILE="/home/yi-hack/config/services/mqtt.conf"
IDENTITY_CONF_FILE="/home/yi-hack/config/identity.conf"
ADVERTISE_CONF_FILE="/home/yi-hack/config/services/mqtt_advertise.conf"

# -----------------------------------------------------------------------------
# Defaults per file
# -----------------------------------------------------------------------------
PARMS_SYSTEM="
HTTPD=yes
TELNETD=no
SSHD=yes
FTPD=no
BUSYBOX_FTPD=no
DISABLE_CLOUD=no
REC_WITHOUT_CLOUD=no
MQTT=no
RTSP=no
RTSP_STREAM=high
RTSP_AUDIO=no
ONVIF=no
ONVIF_WSDD=yes
ONVIF_PROFILE=high
ONVIF_NETIF=wlan0
TIME_OSD=no
SNAPSHOT=yes
SNAPSHOT_LOW=no
NTPD=yes
NTP_SERVER=pool.ntp.org
PROXYCHAINSNG=no
SWAP_FILE=yes
RTSP_PORT=554
HTTPD_PORT=80
USERNAME=
PASSWORD=
TIMEZONE=
FREE_SPACE=15
FTP_UPLOAD=no
FTP_HOST=
FTP_DIR=
FTP_DIR_TREE=no
FTP_USERNAME=
FTP_PASSWORD=
FTP_FILE_DELETE_AFTER_UPLOAD=yes
SSH_PASSWORD=
CRONTAB=
DEBUG_LOG=no"

PARMS_CAMERA="
SWITCH_ON=yes
SAVE_VIDEO_ON_MOTION=yes
SENSITIVITY=low
SOUND_DETECTION=no
SOUND_SENSITIVITY=80
BABY_CRYING_DETECT=no
LED=yes
ROTATE=no
IR=yes"

PARMS_MQTT="
BROKER_IP=0.0.0.0
BROKER_PORT=1883
BROKER_USER=
BROKER_PASSWORD=
TOPIC_BIRTH_WILL=status
TOPIC_MOTION=motion_detection
TOPIC_MOTION_IMAGE=motion_detection_image
MOTION_IMAGE_DELAY=0.5
TOPIC_MOTION_FILES=motion_files
TOPIC_SOUND_DETECTION=sound_detection
BIRTH_MSG=online
WILL_MSG=offline
MOTION_START_MSG=motion_start
MOTION_STOP_MSG=motion_stop
AI_HUMAN_DETECTION_MSG=human
AI_VEHICLE_DETECTION_MSG=vehicle
AI_ANIMAL_DETECTION_MSG=animal
BABY_CRYING_MSG=crying
SOUND_DETECTION_MSG=sound_detected
KEEPALIVE=120
QOS=1
RETAIN_BIRTH_WILL=1
RETAIN_MOTION=0
RETAIN_MOTION_IMAGE=0
RETAIN_MOTION_FILES=0
RETAIN_SOUND_DETECTION=0"

PARMS_IDENTITY="
MQTT_CLIENT_ID=yi-cam
MQTT_PREFIX=yicam
HOMEASSISTANT_NAME=Yi Camera
HOMEASSISTANT_IDENTIFIERS=yi-cam"

PARMS_ADVERTISE="
LINK_ENABLE=no
LINK_BOOT=no
LINK_CRON=no
LINK_CRONTAB=
LINK_TOPIC=links
LINK_RETAIN=1
LINK_QOS=0
INFO_GLOBAL_ENABLE=no
INFO_GLOBAL_BOOT=no
INFO_GLOBAL_CRON=no
INFO_GLOBAL_CRONTAB=
INFO_GLOBAL_TOPIC=info_global
INFO_GLOBAL_RETAIN=1
INFO_GLOBAL_QOS=0
CAMERA_SETTING_ENABLE=no
CAMERA_SETTING_BOOT=no
CAMERA_SETTING_CRON=no
CAMERA_SETTING_CRONTAB=
CAMERA_SETTING_TOPIC=camera_setting
CAMERA_SETTING_RETAIN=1
CAMERA_SETTING_QOS=0
TELEMETRY_ENABLE=no
TELEMETRY_BOOT=no
TELEMETRY_CRON=no
TELEMETRY_CRONTAB=
TELEMETRY_TOPIC=telemetry
TELEMETRY_RETAIN=1
TELEMETRY_QOS=0
HOMEASSISTANT_ENABLE=no
HOMEASSISTANT_BOOT=no
HOMEASSISTANT_CRON=no
HOMEASSISTANT_CRONTAB=
HOMEASSISTANT_MQTT_PREFIX=homeassistant
HOMEASSISTANT_MANUFACTURER=YI
HOMEASSISTANT_MODEL=
HOMEASSISTANT_RETAIN=1
HOMEASSISTANT_QOS=0"

# -----------------------------------------------------------------------------
# seed_defaults <conf_file> <defaults> : append each missing KEY=value
# -----------------------------------------------------------------------------
seed_defaults() {
    _file="$1"
    _parms="$2"
    mkdir -p "${_file%/*}"
    [ -f "$_file" ] || touch "$_file"
    for _kv in $_parms; do
        [ -z "$_kv" ] && continue
        _key=$(echo "$_kv" | cut -d= -f1)
        grep -q "^$_key=" "$_file" || echo "$_kv" >> "$_file"
    done
}

# -----------------------------------------------------------------------------
# Seed (same order as above)
# -----------------------------------------------------------------------------
seed_defaults "$SYSTEM_CONF_FILE"    "$PARMS_SYSTEM"
seed_defaults "$CAMERA_CONF_FILE"    "$PARMS_CAMERA"
seed_defaults "$MQTT_CONF_FILE"      "$PARMS_MQTT"
seed_defaults "$IDENTITY_CONF_FILE"  "$PARMS_IDENTITY"
seed_defaults "$ADVERTISE_CONF_FILE" "$PARMS_ADVERTISE"
