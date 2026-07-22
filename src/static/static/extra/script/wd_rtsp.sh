#!/bin/sh

# 6.0.1

script_name=$(basename -- "$0")

if pidof "$script_name" -o $$ >/dev/null;then
   echo "Already Running - Quitting"
   exit 1
fi


read MODEL_SUFFIX < /home/app/.camver

# Routed through the output/log view (output.LOG matrix); on NO the view symlinks
# this to /dev/null, so no separate switch is needed here.
LOG_FILE="/home/yi-hack/output/log/wd_rtsp.log"

. /home/yi-hack/base/script/get_config.sh

COUNTER=0
COUNTER_LIMIT=10
INTERVAL=10

# Batch config read, once, before the loop (one builtin pass, no forks; the
# values cannot change under a running watchdog without a service restart).
USER=""; PASSWORD=""; PORT=""; ENABLED=""; STREAM=""; AUDIO=""
load_config services.rtsp USER PASSWORD PORT ENABLED STREAM AUDIO
RTSP_ENABLED=$ENABLED; RTSP_STREAM=$STREAM; RTSP_AUDIO=$AUDIO
load_config system DISABLE_CLOUD

if [[ "$USER" != "" ]] ; then
    USERNAME=$USER
else
    PASSWORD=""   # credentials only apply as a pair (matches the old behavior)
fi

RRTSP_RES=$RTSP_STREAM
RRTSP_AUDIO=$RTSP_AUDIO
RRTSP_MODEL=$MODEL_SUFFIX
RRTSP_PORT=$PORT
if [ ! -z $USERNAME ]; then
    RRTSP_USER="-u $USERNAME"
fi
if [ ! -z $PASSWORD ]; then
    RRTSP_PWD="-w $PASSWORD"
fi

restart_rtsp()
{
    killall -q rRTSPServer
    rRTSPServer -r $RRTSP_RES -a $RRTSP_AUDIO -p $RRTSP_PORT $RRTSP_USER $RRTSP_PWD &
}

restart_grabber()
{
    killall -q rRTSPServer
    killall -q h264grabber
    if [[ $RTSP_STREAM == "low" ]]; then
        h264grabber -r low -m $MODEL_SUFFIX -f &
    fi
    if [[ $RTSP_STREAM == "high" ]]; then
        h264grabber -r high -m $MODEL_SUFFIX -f &
    fi
    if [[ $RTSP_STREAM == "both" ]]; then
        h264grabber -r low -m $MODEL_SUFFIX -f &
        h264grabber -r high -m $MODEL_SUFFIX -f &
    fi
    if [[ $RTSP_AUDIO == "yes" ]]; then
        h264grabber -r AUDIO -m $MODEL_SUFFIX -f &
    fi
    rRTSPServer -r $RRTSP_RES -a $RRTSP_AUDIO -p $RRTSP_PORT $RRTSP_USER $RRTSP_PWD &
}

restart_cloud()
{
    if [[ $DISABLE_CLOUD == "yes" ]] ; then
    (
        cd /home/app
        ./cloud &
    )
    fi
}

restart_mqttv4()
{
    mqttv4 &
}

check_rtsp()
{
    # netstat's stderr is deliberately NOT suppressed and its rc is checked:
    # piping straight into `grep -c` threw both away, so a netstat that failed
    # (or rejected an option on this busybox build) yielded SOCKET=0, which
    # quietly disables the locked-process detection below - the watchdog stays
    # up and reports nothing while never checking anything.
    _ns=$(netstat -ltn)
    if [ $? -ne 0 ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - WARNING: netstat failed, socket check skipped this cycle" >> $LOG_FILE
    fi
    # Fork-free count: only ">0" is ever tested, so match instead of grep -c.
    case "$_ns" in *":$RTSP_PORT "*) SOCKET=1 ;; *) SOCKET=0 ;; esac
    CPU=`top -b -n 1 | awk '/rRTSPServer/ && !/awk/ {v=$8} END {print v}'`

    if [ "$CPU" == "" ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - No running processes, restarting rRTSPServer ..." >> $LOG_FILE
        killall -q rRTSPServer
        sleep 1
        restart_rtsp
        COUNTER=0
    fi
    if [ $SOCKET -gt 0 ]; then
        if [ "$CPU" == "0.0" ]; then
            COUNTER=$((COUNTER+1))
            echo "$(date +'%Y-%m-%d %H:%M:%S') - Detected possible locked process ($COUNTER)" >> $LOG_FILE
            if [ $COUNTER -ge $COUNTER_LIMIT ]; then
                echo "$(date +'%Y-%m-%d %H:%M:%S') - Restarting rtsp process" >> $LOG_FILE
                killall -q rRTSPServer
                sleep 1
                restart_rtsp
                COUNTER=0
           fi
        else
            COUNTER=0
        fi
    fi
}

check_cloud()
{
    CPU=`top -b -n 1 | awk '/cloud/ && !/awk/ {v=$8} END {print v}'`
    if [[ $DISABLE_CLOUD == "yes" ]] ; then
    (
    if [ "$CPU" == "" ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - No running processes, restarting ./cloud & ..." >> $LOG_FILE
        restart_cloud
        COUNTER=0
    fi
    )
    fi
}

check_rmm()
{
    if ! pidof rmm > /dev/null; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - ./rmm is not running, restarting the camera  ..." >> $LOG_FILE
        reboot
    fi
}

check_grabber()
{
    if ! pidof h264grabber > /dev/null; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - No running processes, restarting h264grabber ..." >> $LOG_FILE
        killall -q h264grabber
        sleep 1
        restart_grabber
    fi
}

check_mqttv4()
{
    if ! pidof mqttv4 > /dev/null; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - No running processes, restarting mqttv4 ..." >> $LOG_FILE
        killall -q mqttv4
        sleep 1
        restart_mqttv4
    fi
}

if [[ $RTSP_ENABLED == "no" ]] ; then
    exit
fi

# Re-enabled when its starting
echo "$(date +'%Y-%m-%d %H:%M:%S') - Starting RTSP watchdog..." >> $LOG_FILE

while true
do
    check_grabber
    check_rtsp
    check_rmm
    check_cloud
    check_mqttv4
    if [ $COUNTER -eq 0 ]; then
        sleep $INTERVAL
    fi
done
