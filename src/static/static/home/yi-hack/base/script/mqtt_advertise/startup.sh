#!/bin/sh

export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
ADV_DIR="/home/yi-hack/base/script/mqtt_advertise"

. /home/yi-hack/base/script/get_config.sh

# Config defaults (incl. mqtt_advertise.conf) are ensured at boot by the single
# base/script/check_conf.sh (run from system.sh before this script).

LINK_ENABLE=$(get_config services.mqtt_advertise.LINK_ENABLE)
LINK_BOOT=$(get_config services.mqtt_advertise.LINK_BOOT)
LINK_CRON=$(get_config services.mqtt_advertise.LINK_CRON)
LINK_CRONTAB=$(get_config services.mqtt_advertise.LINK_CRONTAB)
INFO_GLOBAL_ENABLE=$(get_config services.mqtt_advertise.INFO_GLOBAL_ENABLE)
INFO_GLOBAL_BOOT=$(get_config services.mqtt_advertise.INFO_GLOBAL_BOOT)
INFO_GLOBAL_CRON=$(get_config services.mqtt_advertise.INFO_GLOBAL_CRON)
INFO_GLOBAL_CRONTAB=$(get_config services.mqtt_advertise.INFO_GLOBAL_CRONTAB)
CAMERA_SETTING_ENABLE=$(get_config services.mqtt_advertise.CAMERA_SETTING_ENABLE)
CAMERA_SETTING_BOOT=$(get_config services.mqtt_advertise.CAMERA_SETTING_BOOT)
CAMERA_SETTING_CRON=$(get_config services.mqtt_advertise.CAMERA_SETTING_CRON)
CAMERA_SETTING_CRONTAB=$(get_config services.mqtt_advertise.CAMERA_SETTING_CRONTAB)
TELEMETRY_ENABLE=$(get_config services.mqtt_advertise.TELEMETRY_ENABLE)
TELEMETRY_BOOT=$(get_config services.mqtt_advertise.TELEMETRY_BOOT)
TELEMETRY_CRON=$(get_config services.mqtt_advertise.TELEMETRY_CRON)
TELEMETRY_CRONTAB=$(get_config services.mqtt_advertise.TELEMETRY_CRONTAB)
HOMEASSISTANT_ENABLE=$(get_config services.mqtt_advertise.HOMEASSISTANT_ENABLE)
HOMEASSISTANT_BOOT=$(get_config services.mqtt_advertise.HOMEASSISTANT_BOOT)
HOMEASSISTANT_CRON=$(get_config services.mqtt_advertise.HOMEASSISTANT_CRON)
HOMEASSISTANT_CRONTAB=$(get_config services.mqtt_advertise.HOMEASSISTANT_CRONTAB)

if [ "$LINK_ENABLE" == "yes" ]; then
    if [ "$LINK_BOOT" == "yes" ]; then
        $ADV_DIR/mqtt_adv_links.sh &
    fi
    if [ "$LINK_CRON" == "yes" ]; then
        echo "$LINK_CRONTAB  $ADV_DIR/mqtt_adv_links.sh" > /var/spool/cron/crontabs/root
    fi
fi
if [ "$INFO_GLOBAL_ENABLE" == "yes" ]; then
    if [ "$INFO_GLOBAL_BOOT" == "yes" ]; then
        $ADV_DIR/mqtt_adv_info_global.sh &
    fi
    if [ "$INFO_GLOBAL_CRON" == "yes" ]; then
        echo "$INFO_GLOBAL_CRONTAB  $ADV_DIR/mqtt_adv_info_global.sh" > /var/spool/cron/crontabs/root
    fi
fi
if [ "$CAMERA_SETTING_ENABLE" == "yes" ]; then
    if [ "$CAMERA_SETTING_BOOT" == "yes" ]; then
        $ADV_DIR/mqtt_adv_config.sh &
    fi
    if [ "$CAMERA_SETTING_CRON" == "yes" ]; then
        echo "$CAMERA_SETTING_CRONTAB  $ADV_DIR/mqtt_adv_config.sh" > /var/spool/cron/crontabs/root
    fi
    FW_VERSION=$(cat /home/yi-hack/extra/version)

    $ADV_DIR/mqtt_set_config.sh &
fi
if [ "$TELEMETRY_ENABLE" == "yes" ]; then
    if [ "$TELEMETRY_BOOT" == "yes" ]; then
        $ADV_DIR/mqtt_adv_telemetry.sh &
    fi
    if [ "$TELEMETRY_CRON" == "yes" ]; then
        echo "$TELEMETRY_CRONTAB  $ADV_DIR/mqtt_adv_telemetry.sh" > /var/spool/cron/crontabs/root
    fi
fi

# $ADV_DIR/mqtt_adv_homeassistant_clean.sh
if [ "$HOMEASSISTANT_ENABLE" == "yes" ]; then
    if [ "$HOMEASSISTANT_BOOT" == "yes" ]; then
        $ADV_DIR/mqtt_adv_homeassistant.sh &
    fi
    if [ "$HOMEASSISTANT_CRON" == "yes" ]; then
        echo "$HOMEASSISTANT_CRONTAB  $ADV_DIR/mqtt_adv_homeassistant.sh" > /var/spool/cron/crontabs/root
    fi
fi
