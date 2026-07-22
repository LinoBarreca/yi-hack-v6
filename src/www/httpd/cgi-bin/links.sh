#!/bin/sh

# 6.0.1

CONF_FILE="etc/system.conf"


. /home/yi-hack/base/script/get_config.sh

LOCAL_IP_WLAN=$(ifconfig wlan0 | awk '/inet addr/{print substr($2,6)}')
LOCAL_IP_ETH=$(ifconfig eth0 | awk '/inet addr/{print substr($2,6)}')

if [[ $LOCAL_IP_WLAN != "" ]] ; then
    LOCAL_IP=$LOCAL_IP_WLAN
elif [[ $LOCAL_IP_ETH != "" ]] ; then
    LOCAL_IP=$LOCAL_IP_ETH
elif [[ $LOCAL_IP_WLAN == "" ]] && [[ $LOCAL_IP_ETH == "" ]] ; then
    LOCAL_IP="127.0.0.1"
fi

# Batch config reads (one builtin pass per file, no get_config subshells).
# Both files have a PORT key, so save the rtsp values before loading httpd.
load_config services.rtsp PORT ENABLED STREAM AUDIO
RTSP_ENABLED=$ENABLED; RTSP_STREAM=$STREAM; RTSP_AUDIO=$AUDIO
case "$PORT" in
    ''|*[!0-9]*) RTSP_PORT=554 ;;
    *) RTSP_PORT=$PORT ;;
esac
PORT=""
load_config services.httpd PORT
case "$PORT" in
    ''|*[!0-9]*) HTTPD_PORT=80 ;;
    *) HTTPD_PORT=$PORT ;;
esac

if [[ $RTSP_PORT != "554" ]] ; then
    D_RTSP_PORT=:$RTSP_PORT
fi
if [[ $HTTPD_PORT != "80" ]] ; then
    D_HTTPD_PORT=:$HTTPD_PORT
fi

printf "Content-type: application/json\r\n\r\n"
printf "{\n"

if [[ $RTSP_ENABLED == "yes" ]] ; then
    if [[ $RTSP_STREAM == "low" ]] ; then
        printf "\"%s\":\"%s\",\n" "low_res_stream"        "rtsp://$LOCAL_IP$D_RTSP_PORT/ch0_1.h264"
    elif [[ $RTSP_STREAM == "high" ]] ; then
        printf "\"%s\":\"%s\",\n" "high_res_stream"       "rtsp://$LOCAL_IP$D_RTSP_PORT/ch0_0.h264"
    elif [[ $RTSP_STREAM == "both" ]] ; then
        printf "\"%s\":\"%s\",\n" "low_res_stream"        "rtsp://$LOCAL_IP$D_RTSP_PORT/ch0_1.h264"
        printf "\"%s\":\"%s\",\n" "high_res_stream"       "rtsp://$LOCAL_IP$D_RTSP_PORT/ch0_0.h264"
    fi
    if [[ $RTSP_AUDIO != "no" ]] && [[ $RTSP_AUDIO != "none" ]] ; then
        printf "\"%s\":\"%s\",\n" "audio_stream"        "rtsp://$LOCAL_IP$D_RTSP_PORT/ch0_2.h264"
    fi
fi

printf "\"%s\":\"%s\",\n" "low_res_snapshot"      "http://$LOCAL_IP$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=low&watermark=yes"
printf "\"%s\":\"%s\"\n" "high_res_snapshot"      "http://$LOCAL_IP$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=high&watermark=yes"

printf "}"
