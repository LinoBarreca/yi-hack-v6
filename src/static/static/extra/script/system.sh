#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# Boot dispatcher. Lives in flash (base/script) and is launched by S20yi-hack after
# build_view.sh has set up the logical view. Uses the fixed logical paths
# /home/yi-hack/{base,config,extra,output,www} - there is NO YI_HACK_PREFIX and no
# SD-vs-flash detection (the symlink layer decides where extra/output/www point).

YI_HACK_VER=$(cat /home/yi-hack/extra/../version 2>/dev/null)
MODEL_SUFFIX=$(cat /home/app/.camver)

# yi-hack environment: single source (farm-first busybox PATH flip, LD_LIBRARY_PATH,
# TZ, get_config) shared with the login shells (/etc/profile sources it too).
. /home/yi-hack/base/script/env.sh
# base/script appended so helper scripts resolve by name (services only: login
# shells don't need it, so it stays out of env.sh).
export PATH=$PATH:/home/yi-hack/base/script

ulimit -s 1024
mkdir /dev/shm 2>/dev/null

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

# cloudAPI is baked into /home/app at BUILD time (pack_fw.sh bake_app_overlays); no runtime
# re-copy from base/script is needed (a reflash re-bakes it). See TODO.md history.

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
# EXTRA config (services + recording/camera/identity/ptz): only the full
# dispatcher needs it. Runs after apply_config so a share override still gets its
# missing keys topped up. (BASE config was already seeded early in S20.)
/home/yi-hack/base/script/check_conf.sh extra

# Build-time locked settings win over everything: re-stamp them after the seeding
# (a recreated file gets generic defaults, which may differ from the locked values).
/home/yi-hack/base/script/restore_locked_configs.sh

# Fill blank per-camera identity (hostname, MQTT/HA ids) from the factory serial.
# Must run after check_conf (keys exist) and before `hostname -F` + the MQTT
# daemons, which read the resolved values. Hostname priority: config > DHCP > serial.
/home/yi-hack/base/script/set_defaults.sh

hostname -F /home/yi-hack/config/hostname

# Swap: destination is decided by the output matrix; build_view.sh created
# /home/yi-hack/output/swap (a symlink) only if output.SWAP_FILE != NO and the target is writable.
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

# Web (httpd) basic auth - isolated from the RTSP/ONVIF stream credentials.
HTTPD_USER=$(get_config services.httpd.USER)
HTTPD_PASSWORD=$(get_config services.httpd.PASSWORD)
if [ -n "$HTTPD_USER" ] ; then
    echo "/onvif::" > /tmp/httpd.conf
    echo "/:$HTTPD_USER:$HTTPD_PASSWORD" >> /tmp/httpd.conf
    chmod 0600 /tmp/httpd.conf
fi

# RTSP/ONVIF stream credentials (shared; the ONVIF stream URL embeds them).
USERNAME=$(get_config services.rtsp.USER)
PASSWORD=$(get_config services.rtsp.PASSWORD)
if [ -n "$USERNAME" ] ; then
    RTSP_USERPWD=$USERNAME:$PASSWORD@
    ONVIF_USERPWD="user=$USERNAME\npassword=$PASSWORD"
fi

SSH_PASSWORD=$(get_config services.sshd.PASSWORD)
if [ -n "$SSH_PASSWORD" ] ; then
    # Flash-wear: chpasswd rewrites /etc on the rootfs (mtd4) every time. Only run it when the
    # configured password actually changed, tracked by a marker (md5 of the configured pwd;
    # the plaintext already lives in system.conf, so the marker leaks nothing extra). The
    # marker is in config/ (mtd5): a v6 reflash resets rootfs+home together, keeping them in sync.
    _pwmark=$(echo -n "$SSH_PASSWORD" | md5sum | cut -d' ' -f1)
    if [ "$_pwmark" != "$(cat /home/yi-hack/config/.sshpw_applied 2>/dev/null)" ] ; then
        echo "root:$SSH_PASSWORD" | chpasswd --md5
        echo "$_pwmark" > /home/yi-hack/config/.sshpw_applied
    fi
fi

case $(get_config services.rtsp.PORT) in
    ''|*[!0-9]*) RTSP_PORT=554 ;;
    *) RTSP_PORT=$(get_config services.rtsp.PORT) ;;
esac
case $(get_config services.httpd.PORT) in
    ''|*[!0-9]*) HTTPD_PORT=80 ;;
    *) HTTPD_PORT=$(get_config services.httpd.PORT) ;;
esac

# The ntpd daemon runs only with the cloud DISABLED: with the cloud on, the stock
# 'cloud' daemon already syncs the clock (cloudAPI -c 136) and two writers would
# fight. With the cloud off, cloudAPI_fake also does a one-shot NTP sync per
# stock syntime call; this daemon adds continuous discipline on top.
if [[ $(get_config services.ntpd.ENABLED) == "yes" ]] && [[ $(get_config system.DISABLE_CLOUD) == "yes" ]] ; then
    # Wait until all the other processes have been initialized
    sleep 5 && ntpd -p $(get_config services.ntpd.SERVER) &
fi

if [[ $(get_config system.DISABLE_CLOUD) == "no" ]] ; then
    (
        cd /home/app
        # Stock logger first: the cloud daemons sendto its /tmp/logsock (best-effort, DGRAM).
        # Starting it HERE (after build_view) means it (re)opens /tmp/log.txt through our bridge
        # symlink -> the output/log view, so log.txt follows the output.LOG matrix.
        killall log_server; ./log_server &
        killall dispatch
        LD_PRELOAD=/home/yi-hack/extra/lib/ipc_multiplex.so ./dispatch &
        sleep 3
        if [[ $(get_config services.rtsp.TIME_OSD) == "yes" ]] ; then
            echo -ne '\x01\x00\x00\x00' | dd of=/tmp/mmap.info bs=1 seek=0 count=4 conv=notrunc
        fi
        LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib" ./rmm &
        sleep 8
        # Stock mp4record only when the native recorder is off (output.RECORD=NO);
        # otherwise both would write to /tmp/sd/record and collide.
        if [[ $(get_config output.RECORD) == "NO" ]] ; then
            ./mp4record &
        fi
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
        # Stock logger first: the cloud daemons sendto its /tmp/logsock (best-effort, DGRAM).
        # Starting it HERE (after build_view) means it (re)opens /tmp/log.txt through our bridge
        # symlink -> the output/log view, so log.txt follows the output.LOG matrix.
        killall log_server; ./log_server &
        killall dispatch
        LD_PRELOAD=/home/yi-hack/extra/lib/ipc_multiplex.so ./dispatch &
        sleep 3
        if [[ $(get_config services.rtsp.TIME_OSD) == "yes" ]] ; then
            echo -ne '\x01\x00\x00\x00' | dd of=/tmp/mmap.info bs=1 seek=0 count=4 conv=notrunc
        fi
        LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib" ./rmm &
		sleep 8
        # Stock mp4record to SD only when the native recorder is off (see above).
        if [[ $(get_config system.REC_WITHOUT_CLOUD) == "yes" ]] && [[ $(get_config output.RECORD) == "SD" ]] ; then
            cd /home/app
            ./mp4record &
        fi
		sleep 4
        ./cloud &
    )
fi

if [[ $(get_config services.httpd.ENABLED) == "yes" ]] ; then
    # Single logical web path; build_view.sh points it to extra/www (full) or base/www-min (rescue).
    # NOTE: recordings live at /home/yi-hack/output/record; the events CGIs read from there
    # (no www/record bind-mount - extra/www may be read-only CIFS).
    # bare 'httpd' resolves via the base/bin farm to the full PATCHED busybox (onvif CGI
    # routing + auth) - base/bin/extra/bin are first on PATH (set above, farm-first).
    httpd -p $HTTPD_PORT -h /home/yi-hack/www -c /tmp/httpd.conf
fi

if [[ $(get_config services.telnetd.ENABLED) == "yes" ]] ; then
    telnetd
fi

case $(get_config services.ftpd.ENABLED) in
    busybox)
        tcpsvd -vE 0.0.0.0 21 ftpd -w &
        ;;
    pureftpd)
        pure-ftpd -B
        ;;
esac

if [[ $(get_config services.sshd.ENABLED) == "yes" ]] ; then
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

# mqtt-config = remote configuration surface (cmnd/#, every parameter): own
# gate so state publishing (mqttv4) can stay on with remote config off. The
# HA camera-setting entities publish on cmnd/ and need it.
if [[ $(get_config services.mqtt.ENABLED) == "yes" ]] ; then
    if [[ $(get_config services.mqtt.CONFIG_ENABLED) == "yes" ]] ; then
        mqtt-config &
    fi
fi

if [[ $RTSP_PORT != "554" ]] ; then
    D_RTSP_PORT=:$RTSP_PORT
fi

if [[ $HTTPD_PORT != "80" ]] ; then
    D_HTTPD_PORT=:$HTTPD_PORT
fi

# services.snapshot.ENABLED is now a 3-way no|legacy|v6 selector (which capture
# backend, imggrabber or hwsnap -- see take_snapshot.sh/cgi-bin/snapshot.sh);
# "no" is still the literal disable value both backends check directly.
if [[ $(get_config services.snapshot.ENABLED) == "no" ]] ; then
    touch /tmp/snapshot.disabled
fi

# ONVIF snapshot watermark follows the snapshot service setting (single source,
# services/snapshot.conf WATERMARK): appended to the snapurl advertised below.
WATERMARK=""
if [[ $(get_config services.snapshot.WATERMARK) == "yes" ]] ; then
    WATERMARK="&watermark=yes"
fi

# Which snapshot URL each ONVIF profile advertises (services/onvif.conf SNAPSHOT):
# same = the profile's own resolution, high/low = force that resolution for every
# profile, none = no snapurl at all (GetSnapshotUri answers with a SOAP fault and
# clients like Home Assistant grab stills from the RTSP stream instead, which
# offloads the JPEG encode from the camera CPU).
SNAPURL_HIGH="\nsnapurl=http://$RTSP_USERPWD%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=high$WATERMARK"
SNAPURL_LOW="\nsnapurl=http://$RTSP_USERPWD%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=low$WATERMARK"
case "$(get_config services.onvif.SNAPSHOT)" in
    high) SNAP_0=$SNAPURL_HIGH; SNAP_1=$SNAPURL_HIGH ;;
    low)  SNAP_0=$SNAPURL_LOW;  SNAP_1=$SNAPURL_LOW ;;
    none) SNAP_0="";            SNAP_1="" ;;
    *)    SNAP_0=$SNAPURL_HIGH; SNAP_1=$SNAPURL_LOW ;;
esac

RRTSP_MODEL=$MODEL_SUFFIX
RRTSP_RES=$(get_config services.rtsp.STREAM)
RRTSP_AUDIO=$(get_config services.rtsp.AUDIO)
RRTSP_PORT=$(get_config services.rtsp.PORT)
RRTSP_USER=$USERNAME
RRTSP_PWD=$PASSWORD

if [[ $(get_config services.rtsp.ENABLED) == "yes" ]] ; then

    if [[ $MODEL_SUFFIX == "yi_dome" ]] || [[ $MODEL_SUFFIX == "yi_home" ]] ; then
        HIGHWIDTH="1280"
        HIGHHEIGHT="720"
    else
        HIGHWIDTH="1920"
        HIGHHEIGHT="1080"
    fi
    if [[ $(get_config services.rtsp.AUDIO) == "yes" ]]; then
        h264grabber -r audio -m $MODEL_SUFFIX -f &
    fi
    if [[ $(get_config services.rtsp.STREAM) == "low" ]]; then
        h264grabber -r low -m $MODEL_SUFFIX -f &
        ONVIF_PROFILE_1="name=Profile_1\nwidth=640\nheight=360\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_1.h264$SNAP_1\ntype=H264"
    fi
    if [[ $(get_config services.rtsp.STREAM) == "high" ]]; then
        h264grabber -r high -m $MODEL_SUFFIX -f &
        ONVIF_PROFILE_0="name=Profile_0\nwidth=$HIGHWIDTH\nheight=$HIGHHEIGHT\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_0.h264$SNAP_0\ntype=H264"
    fi
    if [[ $(get_config services.rtsp.STREAM) == "both" ]]; then
         h264grabber -r low -m $MODEL_SUFFIX -f &
         h264grabber -r high -m $MODEL_SUFFIX -f &
        if [[ $(get_config services.onvif.PROFILE) == "low" ]] || [[ $(get_config services.onvif.PROFILE) == "both" ]] ; then
            ONVIF_PROFILE_1="name=Profile_1\nwidth=640\nheight=360\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_1.h264$SNAP_1\ntype=H264"
        fi
        if [[ $(get_config services.onvif.PROFILE) == "high" ]] || [[ $(get_config services.onvif.PROFILE) == "both" ]] ; then
            ONVIF_PROFILE_0="name=Profile_0\nwidth=$HIGHWIDTH\nheight=$HIGHHEIGHT\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_0.h264$SNAP_0\ntype=H264"
        fi
    rRTSPServer -r $RRTSP_RES -a $RRTSP_AUDIO -p $RRTSP_PORT -u $RRTSP_USER -w $RRTSP_PWD &
    fi
    /home/yi-hack/extra/script/wd_rtsp.sh &
    # Native MP4 recorder (privacy-safe alternative to stock mp4record). Records
    # the local RTSP stream to the output/record view (RAM/SD/CIFS) whenever
    # output.RECORD != NO; wd_record.sh launches and supervises it. mp4record
    # (SD-only, cloud path) is gated off when the native recorder is active.
    if [[ $(get_config output.RECORD) != "NO" ]] ; then
        /home/yi-hack/extra/script/wd_record.sh &
    fi
fi

if [[ $MODEL_SUFFIX == "yi_dome_1080p" ]] || [[ $MODEL_SUFFIX == "yi_cloud_dome_1080p" ]] ; then
    HW_ID=$(dd bs=1 count=4 skip=660 if=/tmp/mmap.info 2>/dev/null | cut -c1-4)
    SERIAL_NUMBER=$(dd bs=1 count=16 skip=664 if=/tmp/mmap.info 2>/dev/null | cut -c1-16)
else
    HW_ID=$(dd bs=1 count=4 skip=592 if=/tmp/mmap.info 2>/dev/null | cut -c1-4)
    SERIAL_NUMBER=$(dd bs=1 count=16 skip=596 if=/tmp/mmap.info 2>/dev/null | cut -c1-16)
fi

if [[ $(get_config services.onvif.ENABLED) == "yes" ]] ; then
    if [[ $(get_config services.onvif.NETIF) == "wlan0" ]] ; then
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
        echo "set_preset=/home/yi-hack/extra/script/ptz_presets.sh -a add_preset -m %s" >> $ONVIF_SRVD_CONF
        echo "set_home_position=/home/yi-hack/extra/script/ptz_presets.sh -a set_home_position" >> $ONVIF_SRVD_CONF
        echo "remove_preset=/home/yi-hack/extra/script/ptz_presets.sh -a del_preset -n %d" >> $ONVIF_SRVD_CONF
        echo "jump_to_abs=/home/yi-hack/extra/bin/ipc_cmd -j %f,%f" >> $ONVIF_SRVD_CONF
        echo "jump_to_rel=/home/yi-hack/extra/bin/ipc_cmd -J %f,%f" >> $ONVIF_SRVD_CONF
        echo "get_presets=/home/yi-hack/extra/script/ptz_presets.sh -a get_presets" >> $ONVIF_SRVD_CONF
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

    if [[ $(get_config services.onvif.WSDD) == "yes" ]] ; then
        wsd_simple_server --pid_file /var/run/wsd_simple_server.pid --if_name $ONVIF_NETIF --xaddr "http://%s$D_HTTPD_PORT/onvif/device_service" -m yi_hack -n Yi
    fi
fi

# Add crontab
CRONTAB=$(get_config system.CRONTAB)
FREE_SPACE=$(get_config recording.FREE_SPACE)
mkdir -p /var/spool/cron/crontabs/
if [ ! -z "$CRONTAB" ]; then
    echo "$CRONTAB" > /var/spool/cron/crontabs/root
fi
if [ "$FREE_SPACE" != "0" ]; then
    # Append (>>), don't overwrite: the recording free-space cleanup must coexist with the
    # user's scheduled jobs (system.CRONTAB). With > it silently dropped the user crontab
    # whenever FREE_SPACE != 0 (the default is 10). /var/spool is tmpfs (fresh each boot),
    # so no cross-boot accumulation.
    echo "0 * * * * /home/yi-hack/extra/script/clean_records.sh $FREE_SPACE" >> /var/spool/cron/crontabs/root
fi

crond -c /var/spool/cron/crontabs/

# Add MQTT Advertise
if [ -f "/home/yi-hack/extra/script/mqtt_advertise/startup.sh" ]; then
    /home/yi-hack/extra/script/mqtt_advertise/startup.sh
fi

if [[ $(get_config services.ftp_upload.ENABLED) == "yes" ]] ; then
    /home/yi-hack/extra/script/ftppush.sh start &
fi

# Optional payload-provided startup hook
if [ -f "/home/yi-hack/extra/startup.sh" ]; then
    /home/yi-hack/extra/startup.sh
fi

# First run on startup, then every day via crond
/home/yi-hack/extra/script/check_update.sh

crond -c /home/yi-hack/config/crontabs
