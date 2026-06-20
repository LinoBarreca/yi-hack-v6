#!/bin/sh

# 0.1.0


get_conf_type()
{
    local IFS="="      # Set IFS to "=" to easily split query string
    set -- $QUERY_STRING
    [ "$1" = "conf" ] && echo "$2"
}

printf "Content-type: application/json\r\n\r\n"

CONF_TYPE="$(get_conf_type)"
CONF_FILE=""

# Per-service config files live under config/services/; the rest (system,
# recording, camera, identity, output) at config/ top level.
case "$CONF_TYPE" in
    snapshot|httpd|rtsp|onvif|telnetd|sshd|ftpd|ftp_upload|ntpd|proxychains|mqtt|mqtt_advertise)
        CONF_FILE="/home/yi-hack/config/services/$CONF_TYPE.conf" ;;
    *)
        CONF_FILE="/home/yi-hack/config/$CONF_TYPE.conf" ;;
esac

printf "{\n"

while read -r LINE ; do
    case $LINE in
        \#*) continue ;;         # Skip comments
        *=*) KEY=${LINE%=*}      # Get key before first "="
             VALUE=${LINE#*=}    # Get value after first "="
             printf "\"%s\":\"%s\",\n" "$KEY" "${VALUE//\"/\\\"}" ;;  # Escape double quotes in value
    esac
done < "$CONF_FILE"

if [ "$CONF_TYPE" = "system" ] ; then
    HOSTNAME=$(cat "/home/yi-hack/config/hostname")
    printf "\"%s\":\"%s\",\n" "HOSTNAME" "${HOSTNAME//\"/\\\"}"  # Escape double quotes in hostname
fi

if [ "$CONF_TYPE" = "camera" ] ; then
    HOMEVER=$(cat /home/homever)
    printf "\"%s\":\"%s\",\n" "HOMEVER" "$HOMEVER"
fi

printf "\"%s\":\"%s\"\n" "NULL" "NULL"  # Add empty key-value pair to "close" the JSON object

printf "}"
