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

# 6.0.1 - yi-hack-v6
#
# Boot dispatcher. Lives in flash (base/script) and is launched by S20yi-hack after
# build_view.sh has set up the logical view. Uses the fixed logical paths
# /home/yi-hack/{base,config,extra,output,www} - there is NO YI_HACK_PREFIX and no
# SD-vs-flash detection (the symlink layer decides where extra/output/www point).

YI_HACK_VER=""; read YI_HACK_VER < /home/yi-hack/extra/../version
read MODEL_SUFFIX < /home/app/.camver

# yi-hack environment: single source (farm-first busybox PATH flip, LD_LIBRARY_PATH,
# TZ, get_config) shared with the login shells (/etc/profile sources it too).
. /home/yi-hack/base/script/env.sh
. /home/yi-hack/extra/script/url_helpers.sh   # urlencode (credentialed URLs)
# base/script appended so helper scripts resolve by name (services only: login
# shells don't need it, so it stays out of env.sh).
export PATH=$PATH:/home/yi-hack/base/script

ulimit -s 1024
# mkdir (no -p): "already exists" is the normal case and the only expected
# failure, so test instead of blanket-suppressing a real error.
[ -d /dev/shm ] || mkdir /dev/shm

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

# Loopback. Nothing in the stock boot configures it, so 127.0.0.1 has NO address and
# anything addressing the camera as localhost cannot connect - `ifconfig lo` shows the
# interface with no "inet addr" line at all (busybox also omits the UP/RUNNING words,
# so read the address line, not the flags). That silently broke the recorder:
# record.sh pulls the camera's own stream from rtsp://...@127.0.0.1:554/, so recording
# wrote nothing at all, video included. The CGI links.sh uses 127.0.0.1 too.
#
# Here rather than in base/system_init.sh because both consumers ship in the extra
# payload and only exist on this branch - nothing in the base/rescue path uses
# loopback - and this way the fix rides a payload sync instead of a home reflash.
# Must stay ABOVE the service launches below. Idempotent, one fork.
ifconfig lo 127.0.0.1 up

# ---- Batch config load ----
# One builtin pass per file (load_config); the old one-get_config-per-key style
# made 43 subshells x 3 forks ≈ 8s of boot time on this CPU. Must stay after
# check_conf/restore_locked_configs/set_defaults above - they seed and patch the
# very keys read here. Generic key names (USER/PASSWORD/PORT/ENABLED) exist in
# several files, so each load is renamed into per-service variables right away.
USER=""; PASSWORD=""; PORT=""; ENABLED=""
load_config services.httpd USER PASSWORD PORT ENABLED
HTTPD_USER=$USER; HTTPD_PASSWORD=$PASSWORD; HTTPD_ENABLED=$ENABLED
case $PORT in
    ''|*[!0-9]*) HTTPD_PORT=80 ;;
    *) HTTPD_PORT=$PORT ;;
esac

USER=""; PASSWORD=""; PORT=""; ENABLED=""; STREAM=""; AUDIO=""; TIME_OSD=""
load_config services.rtsp USER PASSWORD PORT ENABLED STREAM AUDIO TIME_OSD
USERNAME=$USER; RTSP_PASSWORD=$PASSWORD; RTSP_ENABLED=$ENABLED
RTSP_STREAM=$STREAM; RTSP_AUDIO=$AUDIO; RTSP_TIME_OSD=$TIME_OSD
RTSP_PORT_RAW=$PORT   # rRTSPServer historically gets the raw value, not the default
case $PORT in
    ''|*[!0-9]*) RTSP_PORT=554 ;;
    *) RTSP_PORT=$PORT ;;
esac

PASSWORD=""; ENABLED=""
load_config services.sshd PASSWORD ENABLED
SSH_PASSWORD=$PASSWORD; SSHD_ENABLED=$ENABLED

ENABLED=""; SERVER=""
load_config services.ntpd ENABLED SERVER
NTPD_ENABLED=$ENABLED; NTPD_SERVER=$SERVER

ENABLED=""; load_config services.telnetd ENABLED; TELNETD_ENABLED=$ENABLED
ENABLED=""; load_config services.ftpd ENABLED;    FTPD_ENABLED=$ENABLED

ENABLED=""; CONFIG_ENABLED=""
load_config services.mqtt ENABLED CONFIG_ENABLED
MQTT_ENABLED=$ENABLED; MQTT_CONFIG_ENABLED=$CONFIG_ENABLED

ENABLED=""; WATERMARK=""
load_config services.snapshot ENABLED WATERMARK
SNAPSHOT_ENABLED=$ENABLED; SNAPSHOT_WATERMARK=$WATERMARK

ENABLED=""; SNAPSHOT=""; NETIF=""; PROFILE=""; WSDD=""
load_config services.onvif ENABLED SNAPSHOT NETIF PROFILE WSDD
ONVIF_ENABLED=$ENABLED; ONVIF_SNAPSHOT=$SNAPSHOT
ONVIF_NETIF_CFG=$NETIF; ONVIF_PROFILE_CFG=$PROFILE; ONVIF_WSDD=$WSDD

ENABLED=""; load_config services.ftp_upload ENABLED; FTP_UPLOAD_ENABLED=$ENABLED
load_config system DISABLE_CLOUD REC_WITHOUT_CLOUD CRONTAB
load_config output RECORD
load_config recording FREE_SPACE
# camera.LED decides the FINAL LED state at the end of this script. The boot
# phases before it are shown regardless: they are diagnostics, not decoration,
# and a camera that never lights up while it is starting cannot be told apart
# from one that is not starting at all. LED=no means "dark once it is running".
LED=""; load_config camera LED; CAMERA_LED=$LED

# Native pipeline selector (pipeline.conf). Generic MODE/LDC renamed at once; the
# native block further down consumes PIPELINE_MODE/PIPELINE_LDC (no get_config
# there - this is the boot path). Nothing between here and that block rewrites
# pipeline.conf, so reading it now is equivalent to reading it there.
MODE=""; LDC=""
load_config pipeline MODE LDC
PIPELINE_MODE=$MODE; PIPELINE_LDC=$LDC
# ---- End batch config load ----

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
if [ -n "$HTTPD_USER" ] ; then
    echo "/onvif::" > /tmp/httpd.conf
    echo "/:$HTTPD_USER:$HTTPD_PASSWORD" >> /tmp/httpd.conf
    chmod 0600 /tmp/httpd.conf
fi

# RTSP/ONVIF stream credentials. The ONVIF stream URL embeds them as
# user:password@, so they must be percent-encoded - a password with URL-reserved
# characters (@ : ; $ ...) otherwise corrupts the URL and ONVIF clients (go2rtc,
# VLC) fail to open the stream. ONVIF_USERPWD stays raw: those are separate
# user=/password= config fields (used for digest auth), not part of a URL.
if [ -n "$USERNAME" ] ; then
    urlencode "$USERNAME" RTSP_USER_ENC
    urlencode "$RTSP_PASSWORD" RTSP_PWD_ENC
    RTSP_USERPWD=$RTSP_USER_ENC:$RTSP_PWD_ENC@
    ONVIF_USERPWD="user=$USERNAME\npassword=$RTSP_PASSWORD"
fi

if [ -n "$SSH_PASSWORD" ] ; then
    # Flash-wear: chpasswd rewrites /etc on the rootfs (mtd4) every time. Only run it when the
    # configured password actually changed, tracked by a marker (md5 of the configured pwd;
    # the plaintext already lives in system.conf, so the marker leaks nothing extra). The
    # marker is in config/ (mtd5): a v6 reflash resets rootfs+home together, keeping them in sync.
    _pwmark=$(echo -n "$SSH_PASSWORD" | md5sum | cut -d' ' -f1)
    _pwapplied=""; read _pwapplied 2>/dev/null < /home/yi-hack/config/.sshpw_applied
    if [ "$_pwmark" != "$_pwapplied" ] ; then
        echo "root:$SSH_PASSWORD" | chpasswd --md5
        echo "$_pwmark" > /home/yi-hack/config/.sshpw_applied
    fi
fi

# Local event bus. Motion (and, in stock mode, the AI/sound events) is signalled
# by marker files under /tmp/ipc: ipc2file writes them in stock mode, campipe in
# native mode, and both mqttv4 (inotify) and onvif_notify_server watch them.
# Create the dir once here so no producer/consumer races on it at boot (in
# particular onvif_notify_server aborts if the watched dir is missing).
mkdir -p /tmp/ipc

# --- Native MPP pipeline (PIPELINE=online|offline) --------------------------
# pipeline.MODE selects the media pipeline: `stock` = the Xiaomi stack (default),
# `online`/`offline` = the v6 native pipeline (campipe). online is lowest
# latency/RAM; offline adds lens distortion correction (LDC). When native we
# DON'T start the stock media stack (rmm/dispatch/cloud/p2p/oss/watch_process)
# nor the /tmp/view scraper (h264grabber) nor the rmm watchdog (wd_rtsp reboots
# on rmm-gone); native_pipeline.sh reloads the SDK modules, runs campipe and
# supervises it without rebooting. watch_process normally feeds the hardware
# watchdog; since we skip it, we feed /dev/watchdog ourselves (NOW, before the
# ~10s module reload).
#
# Safety: native activates only if MODEL=y20 AND the SDK modules + campipe are
# present - otherwise it silently stays stock (so a native config on a build
# without the assets never breaks boot). Physical escape hatch that survives a
# bad flash config: `touch /tmp/sd/NO_NATIVE` forces stock regardless of the
# configured mode; pulling the SD removes it. (The config pipeline.MODE is the
# normal control - there is deliberately no "force native" flag, so an explicit
# `stock` selection is always honoured.)
# Native pipeline assets, shipped in the SD/CIFS payload (see install.campipe):
#   modules -> extra/lib/modules/<ver>/ , campipe -> extra/bin/campipe .
NATIVE_KO_VER=1.0.4.0
NATIVE_KO_DIR=/home/yi-hack/extra/lib/modules/$NATIVE_KO_VER
NATIVE_BIN=/home/yi-hack/extra/bin/campipe

[ -f /tmp/sd/NO_NATIVE ] && PIPELINE_MODE=stock

NATIVE_PIPELINE=no
if { [ "$PIPELINE_MODE" = "online" ] || [ "$PIPELINE_MODE" = "offline" ]; } \
   && [ "$MODEL_SUFFIX" = "y20" ] \
   && [ -f "$NATIVE_KO_DIR/load3518e" ] && [ -x "$NATIVE_BIN" ] ; then
    NATIVE_PIPELINE=yes
    NATIVE_LDC=0
    [ "$PIPELINE_MODE" = "offline" ] && NATIVE_LDC=$PIPELINE_LDC
    echo "system.sh: native pipeline mode=$PIPELINE_MODE ldc=$NATIVE_LDC"
    # Feed the hardware watchdog ourselves; must run NOW so the box survives the
    # ~10s module reload native_pipeline.sh does.
    ( exec 3>/dev/watchdog; while : ; do printf . >&3 2>/dev/null; sleep 15; done ) &
    # h264grabber (the /tmp/view scraper) is a no-op in native: campipe writes the
    # FIFOs directly. Shadow it for the RTSP-section launches below.
    h264grabber() { : ; }
    # Native media supervisor: SDK module reload + campipe + rRTSPServer, no reboot.
    /home/yi-hack/extra/script/native_pipeline.sh "$PIPELINE_MODE" "$NATIVE_LDC" "$NATIVE_KO_DIR" "$NATIVE_BIN" &
elif [ "$PIPELINE_MODE" != "stock" ] ; then
    echo "system.sh: pipeline.MODE=$PIPELINE_MODE requested but native assets/model missing - staying stock"
fi

# --- Status LED handoff (stock path only) -----------------------------------
# On the stock path the LEDs are rmm's, not ours: we drove them through the boot
# because rmm did not exist yet, and here - the last moment before any stock
# binary starts - we give them back. Unloading rather than just leaving it alone
# matters because the stock loader is lazy AND conditional: it insmods only when
# /dev/cpld_periph is absent, so a module we loaded would be silently adopted,
# and stock would never get to choose between cpld_periph.ko and the _v3 variant
# (see system_init.sh for why that choice is not ours to make). rmm reloads it
# within seconds of starting.
#
# Nothing has the device open at this point - ledctl closes its fd on exit and
# no stock binary has started yet - so the unload should succeed; if it does not,
# say so rather than leaving a silently adopted module behind.
# The device node is the module's own (misc_register), so testing it with a
# builtin says whether the module is loaded without forking lsmod+grep.
if [ "$NATIVE_PIPELINE" = "no" ] && [ -c /dev/cpld_periph ] ; then
    rmmod cpld_periph || echo "system.sh: rmmod cpld_periph failed - rmm will inherit the module we loaded"
fi

# Time sync. Run ntpd when the cloud is DISABLED (with the cloud on, the stock
# 'cloud' daemon syncs the clock itself - cloudAPI -c 136 - and two writers would
# fight), OR in native pipeline mode. Native mode never starts the stock cloud
# stack (cloudAPI_fake / syntime), so its one-shot NTP sync is absent - and with
# the cloud nominally "on" (DISABLE_CLOUD=no) NOTHING would set the clock, leaving
# it at 1970 (which breaks ONVIF WS-Security timestamps and dates log/recording
# files wrongly). There is no writer conflict in native mode since the stock cloud
# daemon isn't running.
if [[ $NTPD_ENABLED == "yes" ]] && { [[ $DISABLE_CLOUD == "yes" ]] || [[ $NATIVE_PIPELINE == "yes" ]]; } ; then
    # Wait until all the other processes have been initialized
    sleep 5 && ntpd -p $NTPD_SERVER &
fi

if [[ $NATIVE_PIPELINE == "no" ]] && [[ $DISABLE_CLOUD == "no" ]] ; then
    (
        cd /home/app
        # Stock logger first: the cloud daemons sendto its /tmp/logsock (best-effort, DGRAM).
        # Starting it HERE (after build_view) means it (re)opens /tmp/log.txt through our bridge
        # symlink -> the output/log view, so log.txt follows the output.LOG matrix.
        killall log_server; ./log_server &
        killall dispatch
        LD_PRELOAD=/home/yi-hack/extra/lib/ipc_multiplex.so ./dispatch &
        sleep 3
        if [[ $RTSP_TIME_OSD == "yes" ]] ; then
            echo -ne '\x01\x00\x00\x00' | dd of=/tmp/mmap.info bs=1 seek=0 count=4 conv=notrunc
        fi
        LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib" ./rmm &
        sleep 8
        # Stock mp4record only when the native recorder is off (output.RECORD=NO);
        # otherwise both would write to /tmp/sd/record and collide.
        if [[ $RECORD == "NO" ]] ; then
            ./mp4record &
        fi
        ./cloud &
        ./p2p_tnp &
        if [[ $MODEL_SUFFIX != "yi_dome" ]] ; then
            # oss hardware-encrypts uploaded media via /dev/cipher and is the only
            # runtime user of hi_cipher.ko (cloudAPI uses software CyaSSL). Load the
            # module here: it was removed from the stock app/init.sh unconditional
            # insmod, which pinned mmz on every boot and made the native pipeline's
            # load3518e -a fail to reload mmz. The update path loads its own in
            # base/init.sh; native and stock-without-cloud never need it.
            insmod /home/base/hi_cipher.ko
            ./oss &
        fi
        ./watch_process &
    )
fi
if [[ $NATIVE_PIPELINE == "no" ]] && [[ $DISABLE_CLOUD == "yes" ]] ; then
    (
        cd /home/app
        # Stock logger first: the cloud daemons sendto its /tmp/logsock (best-effort, DGRAM).
        # Starting it HERE (after build_view) means it (re)opens /tmp/log.txt through our bridge
        # symlink -> the output/log view, so log.txt follows the output.LOG matrix.
        killall log_server; ./log_server &
        killall dispatch
        LD_PRELOAD=/home/yi-hack/extra/lib/ipc_multiplex.so ./dispatch &
        sleep 3
        if [[ $RTSP_TIME_OSD == "yes" ]] ; then
            echo -ne '\x01\x00\x00\x00' | dd of=/tmp/mmap.info bs=1 seek=0 count=4 conv=notrunc
        fi
        LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib" ./rmm &
		sleep 8
        # Stock mp4record to SD only when the native recorder is off (see above).
        if [[ $REC_WITHOUT_CLOUD == "yes" ]] && [[ $RECORD == "SD" ]] ; then
            cd /home/app
            ./mp4record &
        fi
		sleep 4
        ./cloud &
    )
fi

# Stock mqueue -> event-bus bridge. ipc2file reads dispatch's motion/AI/sound
# mqueue and writes the matching /tmp/ipc marker files. It is the single motion
# source that mqttv4 (inotify) and onvif_notify_server both consume in stock mode,
# so it must run whenever the stock stack runs - independent of ONVIF. In native
# mode campipe writes the marker directly and there is no mqueue, so skip it.
# (pidfile-guarded: the ONVIF block no longer starts it.)
#
# ipc2file opens dispatch's mqueue /dev/mqueue/ipc_dispatch_2 with O_RDONLY and no
# O_CREAT, and exits immediately if it is missing (see ipc2file.c open_queue).
# Observed: at this point in boot that queue does not exist yet, so an ipc2file
# started here dies; started once the queue is present, it stays up. Wait for the
# queue in a background subshell (so the rest of boot is not delayed), then start it.
if [[ $NATIVE_PIPELINE == "no" ]] ; then
    (
        _i=0
        while [ ! -e /dev/mqueue/ipc_dispatch_2 ] && [ $_i -lt 120 ] ; do
            sleep 1
            _i=$((_i + 1))
        done
        ipc2file
    ) &
fi

if [[ $HTTPD_ENABLED == "yes" ]] ; then
    # Single logical web path; build_view.sh points it to extra/www (full) or base/www-min (rescue).
    # NOTE: recordings live at /home/yi-hack/output/record; the events CGIs read from there
    # (no www/record bind-mount - extra/www may be read-only CIFS).
    # bare 'httpd' resolves via the base/bin farm to the full PATCHED busybox (onvif CGI
    # routing + auth) - base/bin/extra/bin are first on PATH (set above, farm-first).
    httpd -p $HTTPD_PORT -h /home/yi-hack/www -c /tmp/httpd.conf
fi

if [[ $TELNETD_ENABLED == "yes" ]] ; then
    telnetd
fi

case $FTPD_ENABLED in
    busybox)
        tcpsvd -vE 0.0.0.0 21 ftpd -w &
        ;;
    pureftpd)
        pure-ftpd -B
        ;;
esac

if [[ $SSHD_ENABLED == "yes" ]] ; then
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
if [[ $MQTT_ENABLED == "yes" ]] ; then
    if [[ $MQTT_CONFIG_ENABLED == "yes" ]] ; then
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
if [[ $SNAPSHOT_ENABLED == "no" ]] ; then
    touch /tmp/snapshot.disabled
fi

# ONVIF snapshot watermark follows the snapshot service setting (single source,
# services/snapshot.conf WATERMARK): appended to the snapurl advertised below.
WATERMARK=""
if [[ $SNAPSHOT_WATERMARK == "yes" ]] ; then
    WATERMARK="&watermark=yes"
fi

# Which snapshot URL each ONVIF profile advertises (services/onvif.conf SNAPSHOT):
# same = the profile's own resolution, high/low = force that resolution for every
# profile, none = no snapurl at all (GetSnapshotUri answers with a SOAP fault and
# clients like Home Assistant grab stills from the RTSP stream instead, which
# offloads the JPEG encode from the camera CPU).
SNAPURL_HIGH="\nsnapurl=http://$RTSP_USERPWD%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=high$WATERMARK"
SNAPURL_LOW="\nsnapurl=http://$RTSP_USERPWD%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=low$WATERMARK"
case "$ONVIF_SNAPSHOT" in
    high) SNAP_0=$SNAPURL_HIGH; SNAP_1=$SNAPURL_HIGH ;;
    low)  SNAP_0=$SNAPURL_LOW;  SNAP_1=$SNAPURL_LOW ;;
    none) SNAP_0="";            SNAP_1="" ;;
    *)    SNAP_0=$SNAPURL_HIGH; SNAP_1=$SNAPURL_LOW ;;
esac

RRTSP_MODEL=$MODEL_SUFFIX
RRTSP_RES=$RTSP_STREAM
# Stock-pipeline audio codec. Here the audio does not come from campipe but from
# h264grabber scraping the AAC that rmm already produces, so AAC is the ONLY codec
# this path can serve - g711 is encoded by campipe's AENC and exists in native mode
# only. Map it to aac rather than to silence: the user asked for sound, and the
# request that cannot be honoured is the codec, not the audio. "yes" is the legacy
# spelling of "aac" (config files written before the codec became explicit).
case "$RTSP_AUDIO" in
    yes|aac|g711) RRTSP_AUDIO=aac ;;
    *)            RRTSP_AUDIO=no ;;
esac
RRTSP_PORT=$RTSP_PORT_RAW
RRTSP_USER=$USERNAME
RRTSP_PWD=$RTSP_PASSWORD

if [[ $RTSP_ENABLED == "yes" ]] ; then

    if [[ $MODEL_SUFFIX == "yi_dome" ]] || [[ $MODEL_SUFFIX == "yi_home" ]] ; then
        HIGHWIDTH="1280"
        HIGHHEIGHT="720"
    else
        HIGHWIDTH="1920"
        HIGHHEIGHT="1080"
    fi
    # Gate on the NORMALISED codec, not on the raw config value: AUDIO is an enum
    # (no/aac/g711, plus legacy "yes") since the native pipeline gained a codec
    # choice, so testing for "yes" alone left the grabber unstarted - and the
    # stream silent - for everyone whose config says "aac", which is now the
    # shipped default.
    if [[ $RRTSP_AUDIO == "aac" ]]; then
        [[ $RTSP_AUDIO == "g711" ]] && \
            echo "system.sh: services.rtsp AUDIO=g711 needs the native pipeline - serving aac instead"
        h264grabber -r audio -m $MODEL_SUFFIX -f &
    fi
    if [[ $RTSP_STREAM == "low" ]]; then
        h264grabber -r low -m $MODEL_SUFFIX -f &
        ONVIF_PROFILE_1="name=Profile_1\nwidth=640\nheight=360\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_1.h264$SNAP_1\ntype=H264"
    fi
    if [[ $RTSP_STREAM == "high" ]]; then
        h264grabber -r high -m $MODEL_SUFFIX -f &
        ONVIF_PROFILE_0="name=Profile_0\nwidth=$HIGHWIDTH\nheight=$HIGHHEIGHT\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_0.h264$SNAP_0\ntype=H264"
    fi
    if [[ $RTSP_STREAM == "both" ]]; then
         h264grabber -r low -m $MODEL_SUFFIX -f &
         h264grabber -r high -m $MODEL_SUFFIX -f &
        if [[ $ONVIF_PROFILE_CFG == "low" ]] || [[ $ONVIF_PROFILE_CFG == "both" ]] ; then
            ONVIF_PROFILE_1="name=Profile_1\nwidth=640\nheight=360\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_1.h264$SNAP_1\ntype=H264"
        fi
        if [[ $ONVIF_PROFILE_CFG == "high" ]] || [[ $ONVIF_PROFILE_CFG == "both" ]] ; then
            ONVIF_PROFILE_0="name=Profile_0\nwidth=$HIGHWIDTH\nheight=$HIGHHEIGHT\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/ch0_0.h264$SNAP_0\ntype=H264"
        fi
    fi
    # Outside the per-STREAM branches above: this launch used to sit INSIDE the
    # "both" one, so with STREAM=high or low nothing here started the server and
    # the stream only came up when wd_rtsp.sh noticed the missing process on its
    # next tick - a stream that is simply absent for the first ~10s of every boot.
    # In native mode native_pipeline.sh owns rRTSPServer (it passes its own audio
    # settings); don't start a second one here.
    if [[ $NATIVE_PIPELINE == "no" ]] ; then
        rRTSPServer -r $RRTSP_RES -a $RRTSP_AUDIO -p $RRTSP_PORT -u $RRTSP_USER -w $RRTSP_PWD &
    fi
    # wd_rtsp reboots the camera when rmm is gone (check_rmm); in native mode rmm
    # is intentionally not running (native_pipeline.sh supervises campipe/rRTSP
    # without rebooting), so skip it.
    if [[ $NATIVE_PIPELINE == "no" ]] ; then
        /home/yi-hack/extra/script/wd_rtsp.sh &
    fi
    # Native MP4 recorder (privacy-safe alternative to stock mp4record). Records
    # the local RTSP stream to the output/record view (RAM/SD/CIFS) whenever
    # output.RECORD != NO; wd_record.sh launches and supervises it. mp4record
    # (SD-only, cloud path) is gated off when the native recorder is active.
    if [[ $RECORD != "NO" ]] ; then
        /home/yi-hack/extra/script/wd_record.sh &
    fi
fi

load_hw_ids "$MODEL_SUFFIX"

if [[ $ONVIF_ENABLED == "yes" ]] ; then
    if [[ $ONVIF_NETIF_CFG == "wlan0" ]] ; then
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
    echo "input_file=/tmp/ipc/motion_alarm" >> $ONVIF_SRVD_CONF
    echo "#Event 1" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/PeopleDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/ipc/human_detection" >> $ONVIF_SRVD_CONF
    echo "#Event 2" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/VehicleDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/ipc/vehicle_detection" >> $ONVIF_SRVD_CONF
    echo "#Event 3" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/DogCatDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/ipc/animal_detection" >> $ONVIF_SRVD_CONF
    echo "#Event 4" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/BabyCryingDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/ipc/baby_crying" >> $ONVIF_SRVD_CONF
    echo "#Event 5" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:AudioAnalytics/Audio/DetectedSound" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/ipc/sound_detection" >> $ONVIF_SRVD_CONF

    chmod 0600 $ONVIF_SRVD_CONF
    # onvif_simple_server is a CGI: httpd routes /onvif/* to www/onvif/* (shebang ->
    # onvif_simple_server), which reads its default conf /tmp/onvif_simple_server.conf.
    # It is NOT a daemon - the old `onvif_simple_server --conf_file ...` here was a no-op
    # (the binary lives in www/onvif, never on PATH -> command-not-found), so it is removed.
    # ipc2file (the stock mqueue -> /tmp/ipc bridge) is now started unconditionally in
    # the stock section above, so it is no longer launched here; onvif_notify_server just
    # watches /tmp/ipc, fed by ipc2file (stock) or campipe (native).
    onvif_notify_server --conf_file $ONVIF_SRVD_CONF

    if [[ $ONVIF_WSDD == "yes" ]] ; then
        wsd_simple_server --pid_file /var/run/wsd_simple_server.pid --if_name $ONVIF_NETIF --xaddr "http://%s$D_HTTPD_PORT/onvif/device_service" -m yi_hack -n Yi
    fi
fi

# Add crontab (CRONTAB and FREE_SPACE come from the batch config load above)
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

if [[ $FTP_UPLOAD_ENABLED == "yes" ]] ; then
    /home/yi-hack/extra/script/ftppush.sh start &
fi

# Optional payload-provided startup hook
if [ -f "/home/yi-hack/extra/startup.sh" ]; then
    /home/yi-hack/extra/startup.sh
fi

# First run on startup, then every day via crond
/home/yi-hack/extra/script/check_update.sh

crond -c /home/yi-hack/config/crontabs

# --- Status LED, final state (native path only) -----------------------------
# Boot is over: everything this script starts has been started. Steady blue is
# the "nothing to report" state, and leaving a boot phase blinking forever would
# be a lie about where the camera got to.
# Only on the native path - on the stock path the LEDs went back to rmm above,
# and the module is not even loaded here anymore.
# ledctl resolves bare: env.sh puts base/bin on PATH in both of its branches.
if [[ $NATIVE_PIPELINE == "yes" ]] ; then
    if [ "$CAMERA_LED" = "no" ] ; then
        # `off` is the driver's hold-off, not a plain "both off": it also blocks
        # anything that would light them again later.
        ledctl off
    else
        ledctl pattern ready
    fi
fi
