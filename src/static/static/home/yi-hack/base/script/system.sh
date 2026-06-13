#!/bin/sh

# 0.1.0 - yi-hack-v6
#
# Boot dispatcher. Lives in flash (base/script) and is launched by S20yi-hack after
# build_view.sh has set up the logical view. Uses the fixed logical paths
# /home/yi-hack/{base,config,extra,output,www} - there is NO YI_HACK_PREFIX and no
# SD-vs-flash detection (the symlink layer decides where extra/output/www point).

YI_HACK_VER=$(cat /home/yi-hack/extra/../version 2>/dev/null)
MODEL_SUFFIX=$(cat /home/app/.camver)

. /home/yi-hack/base/script/get_config.sh

export LD_LIBRARY_PATH=/lib:/usr/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib:/home/yi-hack/extra/lib:/home/yi-hack/base/lib
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/home/base/tools:/home/yi-hack/base/bin:/home/yi-hack/extra/bin:/home/app/localbin:/home/base:/home/yi-hack/base/script

if [ ! -L "/home/yi-hack/.ash_history" ]; then
    ln -sf /dev/null /home/yi-hack/.ash_history
fi

ulimit -s 1024
mkdir /dev/shm 2>/dev/null

# Remove core files, if any
rm -f /home/yi-hack/extra/bin/core
rm -f /home/yi-hack/www/cgi-bin/core

touch /tmp/httpd.conf

# Firmware upgrade staged on SD (v5 web-UI "upload firmware" mechanism).
# TODO v6: revisit - the v6 update model is "update the payload on the share, then
# reboot". Kept here for the SD-payload path.
YI_HACK_UPGRADE_PATH="/tmp/sd/$MODEL_SUFFIX"
if [ -f "$YI_HACK_UPGRADE_PATH/yi-hack/fw_upgrade_in_progress" ]; then
    echo "#!/bin/sh" > /tmp/fw_upgrade_2p.sh
    echo "# Complete fw upgrade and restore configuration" >> /tmp/fw_upgrade_2p.sh
    echo "sleep 1" >> /tmp/fw_upgrade_2p.sh
    echo "cd $YI_HACK_UPGRADE_PATH" >> /tmp/fw_upgrade_2p.sh
    echo "cp -rf * .." >> /tmp/fw_upgrade_2p.sh
    echo "cd .." >> /tmp/fw_upgrade_2p.sh
    echo "rm -rf $YI_HACK_UPGRADE_PATH" >> /tmp/fw_upgrade_2p.sh
    echo "rm /home/yi-hack/extra/fw_upgrade_in_progress" >> /tmp/fw_upgrade_2p.sh
    echo "sync" >> /tmp/fw_upgrade_2p.sh
    echo "sync" >> /tmp/fw_upgrade_2p.sh
    echo "sync" >> /tmp/fw_upgrade_2p.sh
    echo "reboot" >> /tmp/fw_upgrade_2p.sh
    sh /tmp/fw_upgrade_2p.sh
    exit
fi

# Update cloudAPI_fake if necessary
if [[ "$(grep -m 3 -n '' /home/app/cloudAPI_fake | tail -n 1 | cut -d ':' -f 2 | cut -c 3-)" != "$(grep -m 3 -n '' /home/yi-hack/base/script/cloudAPI_fake | tail -n 1 | cut -d ':' -f 2 | cut -c 3-)" ]]; then
  cp -f /home/yi-hack/base/script/cloudAPI_fake /home/app/
fi

# Update cloudAPI if necessary
if [[ "$(grep -m 3 -n '' /home/app/cloudAPI | tail -n 1 | cut -d ':' -f 2 | cut -c 3-)" != "$(grep -m 3 -n '' /home/yi-hack/base/script/cloudAPI | tail -n 1 | cut -d ':' -f 2 | cut -c 3-)" ]]; then
  cp -f /home/yi-hack/base/script/cloudAPI /home/app/
fi

# Manual Wi-Fi config (recovery assets stay on the physical SD)
if [ -f /tmp/sd/recover/configure_wifi.cfg ]; then
	mv /tmp/sd/recover/configure_wifi.cfg /tmp/configure_wifi.cfg
	sync
	sh /home/yi-hack/base/script/configure_wifi.sh
fi

if [ -f "/tmp/sd/recover/mtdblock2_recover.bin" ]; then
	sync
	sh /home/yi-hack/base/script/configure_wifi.sh
fi
/home/yi-hack/base/script/check_conf.sh

hostname -F /home/yi-hack/config/hostname

export TZ=$(get_config system.TIMEZONE)

# Swap: destination is decided by the output matrix; build_view.sh created
# /home/yi-hack/output/swap (a symlink) only if output.SWAP != NO and the target is writable.
if [ -d /home/yi-hack/output/swap ]; then
    SWAPFILE=/home/yi-hack/output/swap/swapfile
    if [ -f "$SWAPFILE" ]; then
        swapon "$SWAPFILE"
    else
        dd if=/dev/zero of="$SWAPFILE" bs=1M count=64
        chmod 0600 "$SWAPFILE"
        mkswap "$SWAPFILE"
        swapon "$SWAPFILE"
    fi
    sysctl -w vm.dirty_background_ratio=2
    sysctl -w vm.dirty_ratio=5
    sysctl -w vm.dirty_writeback_centisecs=100
    sysctl -w vm.dirty_expire_centisecs=500
    sysctl -w vm.vfs_cache_pressure=200
    sysctl -w vm.swappiness=60
    sysctl -w vm.laptop_mode=5
fi

if [[ x$(get_config system.USERNAME) != "x" ]] ; then
    USERNAME=$(get_config system.USERNAME)
    PASSWORD=$(get_config system.PASSWORD)
    RTSP_USERPWD=$USERNAME:$PASSWORD@
    ONVIF_USERPWD="user=$USERNAME\npassword=$PASSWORD"
    echo "/onvif::" > /tmp/httpd.conf
    echo "/:$USERNAME:$PASSWORD" >> /tmp/httpd.conf
    chmod 0600 /tmp/httpd.conf
fi

if [[ x$(get_config system.SSH_PASSWORD) != "x" ]] ; then
    SSH_PASSWORD=$(get_config system.SSH_PASSWORD)
    echo root:$SSH_PASSWORD | chpasswd --md5
fi

case $(get_config system.RTSP_PORT) in
    ''|*[!0-9]*) RTSP_PORT=554 ;;
    *) RTSP_PORT=$(get_config system.RTSP_PORT) ;;
esac
case $(get_config system.HTTPD_PORT) in
    ''|*[!0-9]*) HTTPD_PORT=80 ;;
    *) HTTPD_PORT=$(get_config system.HTTPD_PORT) ;;
esac

if [[ $(get_config system.NTPD) == "yes" ]] ; then
    # Wait until all the other processes have been initialized
    sleep 5 && ntpd -p $(get_config system.NTP_SERVER) &
fi

if [[ $(get_config system.DISABLE_CLOUD) == "no" ]] ; then
    (
        cd /home/app
        killall dispatch
        LD_PRELOAD=/home/yi-hack/base/lib/ipc_multiplex.so ./dispatch &
        sleep 3
        if [[ $(get_config system.TIME_OSD) == "yes" ]] ; then
            echo -ne '\x01\x00\x00\x00' | dd of=/tmp/mmap.info bs=1 seek=0 count=4 conv=notrunc
        fi
        LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib" ./rmm &
        sleep 8
        ./mp4record &
        ./cloud &
        ./p2p_tnp &
        if [[ $(cat /home/app/.camver) != "yi_dome" ]] ; then
            ./oss &
        fi
        ./watch_process &
    )
fi
if [[ $(get_config system.DISABLE_CLOUD) == "yes" ]] ; then
    (
        cd /home/app
        killall dispatch
        LD_PRELOAD=/home/yi-hack/base/lib/ipc_multiplex.so ./dispatch &
        sleep 3
        if [[ $(get_config system.TIME_OSD) == "yes" ]] ; then
            echo -ne '\x01\x00\x00\x00' | dd of=/tmp/mmap.info bs=1 seek=0 count=4 conv=notrunc
        fi
        LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib" ./rmm &
		sleep 8
        if [[ $(get_config system.REC_WITHOUT_CLOUD) == "yes" ]] ; then
            cd /home/app
            ./mp4record &
        fi
		sleep 4
        ./cloud &
    )
fi

if [[ $(get_config system.HTTPD) == "yes" ]] ; then
    # Single logical web path; build_view.sh points it to extra/www (full) or base/www-min (rescue).
    # NOTE: recordings live at /home/yi-hack/output/record; the events CGIs read from there
    # (no www/record bind-mount - extra/www may be read-only CIFS).
    # Explicit path: the full UI needs the patched busybox (onvif CGI routing + auth) which
    # ships in the payload (extra/bin). A bare 'httpd' would resolve to the unpatched rootfs
    # busybox first on PATH.
    /home/yi-hack/extra/bin/httpd -p $HTTPD_PORT -h /home/yi-hack/www -c /tmp/httpd.conf
fi

if [[ $(get_config system.TELNETD) == "yes" ]] ; then
    telnetd
fi

if [[ $(get_config system.FTPD) == "yes" ]] ; then
    if [[ $(get_config system.BUSYBOX_FTPD) == "yes" ]] ; then
        tcpsvd -vE 0.0.0.0 21 ftpd -w &
    else
        pure-ftpd -B
    fi
fi

if [[ $(get_config system.SSHD) == "yes" ]] ; then
    mkdir -p /home/yi-hack/config/dropbear
    if [ ! -f /home/yi-hack/config/dropbear/dropbear_ecdsa_host_key ]; then
        dropbearkey -t ecdsa -f /tmp/dropbear_ecdsa_host_key
        mv /tmp/dropbear_ecdsa_host_key /home/yi-hack/config/dropbear/
    fi
    if [ ! -f /home/yi-hack/config/dropbear/dropbear_ed25519_host_key ]; then
        dropbearkey -t ed25519 -f /tmp/dropbear_ed25519_host_key
        mv /tmp/dropbear_ed25519_host_key /home/yi-hack/config/dropbear/
    fi
    chmod 0600 /home/yi-hack/config/dropbear/*
    dropbear -R -B
fi

mqttv4 &

if [[ $(get_config system.MQTT) == "yes" ]] ; then
    mqtt-config &
    /home/yi-hack/base/script/conf2mqtt.sh &
fi

if [[ $RTSP_PORT != "554" ]] ; then
    D_RTSP_PORT=:$RTSP_PORT
fi

if [[ $HTTPD_PORT != "80" ]] ; then
    D_HTTPD_PORT=:$HTTPD_PORT
fi

if [[ $(get_config system.SNAPSHOT) == "no" ]] ; then
    touch /tmp/snapshot.disabled
fi

if [[ $(get_config system.SNAPSHOT_LOW) == "yes" ]] ; then
    touch /tmp/snapshot.low
fi

RRTSP_MODEL=$MODEL_SUFFIX
RRTSP_RES=$(get_config system.RTSP_STREAM)
RRTSP_AUDIO=$(get_config system.RTSP_AUDIO)
RRTSP_PORT=$(get_config system.RTSP_PORT)
RRTSP_USER=$USERNAME
RRTSP_PWD=$PASSWORD

if [[ $(get_config system.RTSP) == "yes" ]] ; then

    if [[ $MODEL_SUFFIX == "yi_dome" ]] || [[ $MODEL_SUFFIX == "yi_home" ]] ; then
        HIGHWIDTH="1280"
        HIGHHEIGHT="720"
    else
        HIGHWIDTH="1920"
        HIGHHEIGHT="1080"
    fi
    if [[ $(get_config system.RTSP_AUDIO) == "yes" ]]; then
        h264grabber -r audio -m $MODEL_SUFFIX -f &
    fi
    if [[ $(get_config system.RTSP_STREAM) == "low" ]]; then
        h264grabber -r low -m $MODEL_SUFFIX -f &
        ONVIF_PROFILE_1="name=Profile_1\nwidth=640\nheight=360\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_1.h264\nsnapurl=http://$RTSP_USERPWD%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=low$WATERMARK\ntype=H264"
    fi
    if [[ $(get_config system.RTSP_STREAM) == "high" ]]; then
        h264grabber -r high -m $MODEL_SUFFIX -f &
        ONVIF_PROFILE_0="name=Profile_0\nwidth=$HIGHWIDTH\nheight=$HIGHHEIGHT\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_0.h264\nsnapurl=http://$RTSP_USERPWD%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=high$WATERMARK\ntype=H264"
    fi
    if [[ $(get_config system.RTSP_STREAM) == "both" ]]; then
         h264grabber -r low -m $MODEL_SUFFIX -f &
         h264grabber -r high -m $MODEL_SUFFIX -f &
        if [[ $(get_config system.ONVIF_PROFILE) == "low" ]] || [[ $(get_config system.ONVIF_PROFILE) == "both" ]] ; then
            ONVIF_PROFILE_1="name=Profile_1\nwidth=640\nheight=360\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_1.h264\nsnapurl=http://$RTSP_USERPWD%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=low$WATERMARK\ntype=H264"
        fi
        if [[ $(get_config system.ONVIF_PROFILE) == "high" ]] || [[ $(get_config system.ONVIF_PROFILE) == "both" ]] ; then
            ONVIF_PROFILE_0="name=Profile_0\nwidth=$HIGHWIDTH\nheight=$HIGHHEIGHT\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_0.h264\nsnapurl=http://$RTSP_USERPWD%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=high$WATERMARK\ntype=H264"
        fi
    rRTSPServer -r $RRTSP_RES -a $RRTSP_AUDIO -p $RRTSP_PORT -u $RRTSP_USER -w $RRTSP_PWD &
    fi
    /home/yi-hack/base/script/wd_rtsp.sh &
fi

if [[ $MODEL_SUFFIX == "yi_dome_1080p" ]] || [[ $MODEL_SUFFIX == "yi_cloud_dome_1080p" ]] ; then
    HW_ID=$(dd bs=1 count=4 skip=660 if=/tmp/mmap.info 2>/dev/null | cut -c1-4)
    SERIAL_NUMBER=$(dd bs=1 count=16 skip=664 if=/tmp/mmap.info 2>/dev/null | cut -c1-16)
else
    HW_ID=$(dd bs=1 count=4 skip=592 if=/tmp/mmap.info 2>/dev/null | cut -c1-4)
    SERIAL_NUMBER=$(dd bs=1 count=16 skip=596 if=/tmp/mmap.info 2>/dev/null | cut -c1-16)
fi

if [[ $(get_config system.ONVIF) == "yes" ]] ; then
    if [[ $(get_config system.ONVIF_NETIF) == "wlan0" ]] ; then
        ONVIF_NETIF="wlan0"
    else
        ONVIF_NETIF="eth0"
    fi

    ONVIF_SRVD_CONF="/tmp/onvif_simple_server.conf"

    echo "model=Yi Hack" > $ONVIF_SRVD_CONF
    echo "manufacturer=Yi" >> $ONVIF_SRVD_CONF
    echo "firmware_ver=$YI_HACK_VER" >> $ONVIF_SRVD_CONF
    echo "hardware_id=$HW_ID" >> $ONVIF_SRVD_CONF
    echo "serial_num=$SERIAL_NUMBER" >> $ONVIF_SRVD_CONF
    echo "ifs=$ONVIF_NETIF" >> $ONVIF_SRVD_CONF
    echo "port=$HTTPD_PORT" >> $ONVIF_SRVD_CONF
    echo "scope=onvif://www.onvif.org/Profile/Streaming" >> $ONVIF_SRVD_CONF
    echo "" >> $ONVIF_SRVD_CONF
    if [ ! -z $ONVIF_USERPWD ]; then
        echo -e $ONVIF_USERPWD >> $ONVIF_SRVD_CONF
        echo "" >> $ONVIF_SRVD_CONF
    fi
    if [ ! -z $ONVIF_PROFILE_0 ]; then
        echo "#Profile 0" >> $ONVIF_SRVD_CONF
        echo -e $ONVIF_PROFILE_0 >> $ONVIF_SRVD_CONF
        echo "" >> $ONVIF_SRVD_CONF
    fi
    if [ ! -z $ONVIF_PROFILE_1 ]; then
        echo "#Profile 1" >> $ONVIF_SRVD_CONF
        echo -e $ONVIF_PROFILE_1 >> $ONVIF_SRVD_CONF
        echo "" >> $ONVIF_SRVD_CONF
    fi

    if [[ $MODEL_SUFFIX == "yi_dome" ]] || [[ $MODEL_SUFFIX == "yi_dome_1080p" ]] || [[ $MODEL_SUFFIX == "yi_cloud_dome_1080p" ]] ; then
        echo "#PTZ" >> $ONVIF_SRVD_CONF
        echo "ptz=1" >> $ONVIF_SRVD_CONF
        echo "get_position=/home/yi-hack/extra/bin/ipc_cmd -g" >> $ONVIF_SRVD_CONF
        echo "is_running=/home/yi-hack/extra/bin/ipc_cmd -u" >> $ONVIF_SRVD_CONF
        echo "move_left=/home/yi-hack/extra/bin/ipc_cmd -m left" >> $ONVIF_SRVD_CONF
        echo "move_right=/home/yi-hack/extra/bin/ipc_cmd -m right" >> $ONVIF_SRVD_CONF
        echo "move_up=/home/yi-hack/extra/bin/ipc_cmd -m up" >> $ONVIF_SRVD_CONF
        echo "move_down=/home/yi-hack/extra/bin/ipc_cmd -m down" >> $ONVIF_SRVD_CONF
        echo "move_stop=/home/yi-hack/extra/bin/ipc_cmd -m stop" >> $ONVIF_SRVD_CONF
        echo "move_preset=/home/yi-hack/extra/bin/ipc_cmd -p %d" >> $ONVIF_SRVD_CONF
        echo "set_preset=/home/yi-hack/base/script/ptz_presets.sh -a add_preset -m %s" >> $ONVIF_SRVD_CONF
        echo "set_home_position=/home/yi-hack/base/script/ptz_presets.sh -a set_home_position" >> $ONVIF_SRVD_CONF
        echo "remove_preset=/home/yi-hack/base/script/ptz_presets.sh -a del_preset -n %d" >> $ONVIF_SRVD_CONF
        echo "jump_to_abs=/home/yi-hack/extra/bin/ipc_cmd -j %f,%f" >> $ONVIF_SRVD_CONF
        echo "jump_to_rel=/home/yi-hack/extra/bin/ipc_cmd -J %f,%f" >> $ONVIF_SRVD_CONF
        echo "get_presets=/home/yi-hack/base/script/ptz_presets.sh -a get_presets" >> $ONVIF_SRVD_CONF
        echo "" >> $ONVIF_SRVD_CONF
    fi

    echo "#EVENT" >> $ONVIF_SRVD_CONF
    echo "events=3" >> $ONVIF_SRVD_CONF
    echo "#Event 0" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:VideoSource/MotionAlarm" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/motion_alarm" >> $ONVIF_SRVD_CONF
    echo "#Event 1" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/PeopleDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/human_detection" >> $ONVIF_SRVD_CONF
    echo "#Event 2" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/VehicleDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/vehicle_detection" >> $ONVIF_SRVD_CONF
    echo "#Event 3" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/DogCatDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/animal_detection" >> $ONVIF_SRVD_CONF
    echo "#Event 4" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/BabyCryingDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/baby_crying" >> $ONVIF_SRVD_CONF
    echo "#Event 5" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:AudioAnalytics/Audio/DetectedSound" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/sound_detection" >> $ONVIF_SRVD_CONF

    chmod 0600 $ONVIF_SRVD_CONF
    # onvif_simple_server is a CGI: httpd routes /onvif/* to www/onvif/* (shebang ->
    # onvif_simple_server), which reads its default conf /tmp/onvif_simple_server.conf.
    # It is NOT a daemon - the old `onvif_simple_server --conf_file ...` here was a no-op
    # (the binary lives in www/onvif, never on PATH -> command-not-found), so it is removed.
    ipc2file
    onvif_notify_server --conf_file $ONVIF_SRVD_CONF

    if [[ $(get_config system.ONVIF_WSDD) == "yes" ]] ; then
        wsd_simple_server --pid_file /var/run/wsd_simple_server.pid --if_name $ONVIF_NETIF --xaddr "http://%s$D_HTTPD_PORT/onvif/device_service" -m yi_hack -n Yi
    fi
fi

framefinder $MODEL_SUFFIX &

# Add crontab
CRONTAB=$(get_config system.CRONTAB)
FREE_SPACE=$(get_config system.FREE_SPACE)
mkdir -p /var/spool/cron/crontabs/
if [ ! -z "$CRONTAB" ]; then
    echo "$CRONTAB" > /var/spool/cron/crontabs/root
fi
if [ "$FREE_SPACE" != "0" ]; then
    echo "0 * * * * /home/yi-hack/base/script/clean_records.sh $FREE_SPACE" > /var/spool/cron/crontabs/root
fi

/usr/sbin/crond -c /var/spool/cron/crontabs/

# Add MQTT Advertise
if [ -f "/home/yi-hack/base/script/mqtt_advertise/startup.sh" ]; then
    /home/yi-hack/base/script/mqtt_advertise/startup.sh
fi

if [[ $(get_config system.FTP_UPLOAD) == "yes" ]] ; then
    /home/yi-hack/base/script/ftppush.sh start &
fi

# Optional payload-provided startup hook
if [ -f "/home/yi-hack/extra/startup.sh" ]; then
    /home/yi-hack/extra/startup.sh
fi

# First run on startup, then every day via crond
/home/yi-hack/base/script/check_update.sh

crond -c /home/yi-hack/config/crontabs
