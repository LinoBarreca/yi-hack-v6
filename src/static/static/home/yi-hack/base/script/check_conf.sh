#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# check_conf.sh [base|extra] - seed default values into the flash config files.
# For each file, any default key that is MISSING is appended; existing keys are
# left untouched (so user/runtime values survive). A missing file is (re)created
# from these defaults, so a deleted known config file self-heals at boot.
#
# Two groups, matching the two boot moments:
#   base  - config needed on EVERY boot, including minimal/rescue (no payload):
#           system, wifi, cifs, output. Read very early (DEBUG_LOG, wifi_up,
#           mount_cifs, build_view), so it is seeded at the top of S20 on BOTH
#           branches, before anything reads it.
#   extra - config for the activatable services, only meaningful with the
#           payload: recording, camera, identity, ptz_presets and services/*.
#           Seeded by system.sh on the full-dispatcher branch (after apply_config,
#           so the share override still gets its missing keys topped up).
#
# No argument (or any other value) seeds BOTH - handy for a manual/standalone run.

: "${CONFIG_DIR:=/home/yi-hack/config}"
MODE="${1:-all}"

# -----------------------------------------------------------------------------
# Config files
# -----------------------------------------------------------------------------
# base
SYSTEM_CONF_FILE="$CONFIG_DIR/system.conf"
WIFI_CONF_FILE="$CONFIG_DIR/wifi.conf"
CIFS_CONF_FILE="$CONFIG_DIR/cifs.conf"
OUTPUT_CONF_FILE="$CONFIG_DIR/output.conf"
# extra
RECORDING_CONF_FILE="$CONFIG_DIR/recording.conf"
CAMERA_CONF_FILE="$CONFIG_DIR/camera.conf"
IDENTITY_CONF_FILE="$CONFIG_DIR/identity.conf"
PTZ_CONF_FILE="$CONFIG_DIR/ptz_presets.conf"
SNAPSHOT_CONF_FILE="$CONFIG_DIR/services/snapshot.conf"
HTTPD_CONF_FILE="$CONFIG_DIR/services/httpd.conf"
RTSP_CONF_FILE="$CONFIG_DIR/services/rtsp.conf"
ONVIF_CONF_FILE="$CONFIG_DIR/services/onvif.conf"
TELNETD_CONF_FILE="$CONFIG_DIR/services/telnetd.conf"
SSHD_CONF_FILE="$CONFIG_DIR/services/sshd.conf"
FTPD_CONF_FILE="$CONFIG_DIR/services/ftpd.conf"
FTP_UPLOAD_CONF_FILE="$CONFIG_DIR/services/ftp_upload.conf"
NTPD_CONF_FILE="$CONFIG_DIR/services/ntpd.conf"
PROXYCHAINS_CONF_FILE="$CONFIG_DIR/services/proxychains.conf"
MQTT_CONF_FILE="$CONFIG_DIR/services/mqtt.conf"
ADVERTISE_CONF_FILE="$CONFIG_DIR/services/mqtt_advertise.conf"

# -----------------------------------------------------------------------------
# Defaults per file - BASE group
# -----------------------------------------------------------------------------
PARMS_SYSTEM="
TIMEZONE=
DEBUG_LOG=no
DISABLE_CLOUD=no
REC_WITHOUT_CLOUD=no
CHECK_UPDATES=no
CRONTAB="

PARMS_WIFI="
SSID=
PSK="

PARMS_CIFS="
ENABLED=no
HOST=
SHARE=
USER=guest
PASS=
SEC=ntlmssp
VERS=1.0
RETRY=10
RETRY_DELAY=6
RW_HOST=
RW_SHARE=
RW_USER=
RW_PASS=
RW_SEC=
RW_VERS="

PARMS_OUTPUT="
RECORD=NO
LOG=RAM
SWAP_FILE=NO"

# -----------------------------------------------------------------------------
# Defaults per file - EXTRA group
# -----------------------------------------------------------------------------
PARMS_RECORDING="
FREE_SPACE=10
SEGMENT_TIME=60"

PARMS_CAMERA="
SWITCH_ON=yes
SAVE_VIDEO_ON_MOTION=yes
SENSITIVITY=low
SOUND_SENSITIVITY=80
LED=yes
ROTATE=no
IR=yes
MIC=yes
SOUND_DETECTION=no
BABY_CRYING_DETECT=no
AI_HUMAN_DETECTION=no
AI_VEHICLE_DETECTION=no
AI_ANIMAL_DETECTION=no"

# Per-camera identity: shipped blank on purpose. set_defaults.sh (run from
# system.sh) fills any empty value from the factory serial on first boot.
PARMS_IDENTITY="
MQTT_CLIENT_ID=
MQTT_PREFIX=
HOMEASSISTANT_NAME=
HOMEASSISTANT_IDENTIFIERS="

PARMS_PTZ="
0=
1=
2=
3=
4=
5=
6=
7="

PARMS_SNAPSHOT="
ENABLED=yes
RESOLUTION=high
WATERMARK=yes"

PARMS_HTTPD="
ENABLED=yes
PORT=80
USER=
PASSWORD="

PARMS_RTSP="
ENABLED=no
STREAM=high
AUDIO=no
AUDIO_NR_LEVEL=0
PORT=554
TIME_OSD=no
USER=
PASSWORD="

PARMS_ONVIF="
ENABLED=no
WSDD=no
PROFILE=high
SNAPSHOT=same
NETIF=wlan0"

PARMS_TELNETD="
ENABLED=no"

PARMS_SSHD="
ENABLED=yes
PASSWORD="

PARMS_FTPD="
ENABLED=no"

PARMS_FTP_UPLOAD="
ENABLED=no
HOST=
DIR=
DIR_TREE=no
USERNAME=
PASSWORD=
FILE_DELETE_AFTER_UPLOAD=no"

PARMS_NTPD="
ENABLED=no
SERVER=pool.ntp.org"

PARMS_PROXYCHAINS="
ENABLED=no"

PARMS_MQTT="
ENABLED=no
CONFIG_ENABLED=yes
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
    # Iterate LINE by line, not word by word: a default value may contain spaces
    # (e.g. "HOMEASSISTANT_NAME=Yi Camera"). An unquoted `for _kv in $_parms` splits
    # on that space and appends the stray "Camera" as a bogus key on EVERY boot.
    echo "$_parms" | while IFS= read -r _kv; do
        [ -z "$_kv" ] && continue
        _key=${_kv%%=*}
        grep -qE "^${_key}=" "$_file" || echo "$_kv" >> "$_file"
    done
}

seed_base() {
    seed_defaults "$SYSTEM_CONF_FILE" "$PARMS_SYSTEM"
    seed_defaults "$WIFI_CONF_FILE"   "$PARMS_WIFI"
    seed_defaults "$CIFS_CONF_FILE"   "$PARMS_CIFS"
    seed_defaults "$OUTPUT_CONF_FILE" "$PARMS_OUTPUT"
}

seed_extra() {
    seed_defaults "$RECORDING_CONF_FILE"   "$PARMS_RECORDING"
    seed_defaults "$CAMERA_CONF_FILE"      "$PARMS_CAMERA"
    seed_defaults "$IDENTITY_CONF_FILE"    "$PARMS_IDENTITY"
    seed_defaults "$PTZ_CONF_FILE"         "$PARMS_PTZ"
    seed_defaults "$SNAPSHOT_CONF_FILE"    "$PARMS_SNAPSHOT"
    seed_defaults "$HTTPD_CONF_FILE"       "$PARMS_HTTPD"
    seed_defaults "$RTSP_CONF_FILE"        "$PARMS_RTSP"
    seed_defaults "$ONVIF_CONF_FILE"       "$PARMS_ONVIF"
    seed_defaults "$TELNETD_CONF_FILE"     "$PARMS_TELNETD"
    seed_defaults "$SSHD_CONF_FILE"        "$PARMS_SSHD"
    seed_defaults "$FTPD_CONF_FILE"        "$PARMS_FTPD"
    seed_defaults "$FTP_UPLOAD_CONF_FILE"  "$PARMS_FTP_UPLOAD"
    seed_defaults "$NTPD_CONF_FILE"        "$PARMS_NTPD"
    seed_defaults "$PROXYCHAINS_CONF_FILE" "$PARMS_PROXYCHAINS"
    seed_defaults "$MQTT_CONF_FILE"        "$PARMS_MQTT"
    seed_defaults "$ADVERTISE_CONF_FILE"   "$PARMS_ADVERTISE"
}

case "$MODE" in
    base)  seed_base ;;
    extra) seed_extra ;;
    *)     seed_base; seed_extra ;;
esac
