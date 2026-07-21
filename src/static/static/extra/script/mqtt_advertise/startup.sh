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

export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
ADV_DIR="/home/yi-hack/extra/script/mqtt_advertise"

. /home/yi-hack/base/script/get_config.sh

# Config defaults (incl. mqtt_advertise.conf) are ensured at boot by the single
# base/script/check_conf.sh (run from system.sh before this script).

# HA advertise rides on top of the MQTT bridge: skip entirely if MQTT is off
# (the advertisers publish to the broker configured in services/mqtt.conf).
if [ "$(get_config services.mqtt.ENABLED)" != "yes" ]; then
    exit 0
fi

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
# Camera-setting commands are handled by mqtt-config (cmnd/camera/<KEY>,
# gated on services/mqtt.conf CONFIG_ENABLED); state is echoed per-key by
# mqttv4 on stat/camera/<key>. Here we only advertise (see
# mqtt_adv_homeassistant.sh) and dump the current state so HA starts populated.
if [ "$CAMERA_SETTING_ENABLE" == "yes" ]; then
    if [ "$CAMERA_SETTING_BOOT" == "yes" ]; then
        /home/yi-hack/extra/script/conf2mqtt.sh camera &
    fi
    if [ "$CAMERA_SETTING_CRON" == "yes" ]; then
        echo "$CAMERA_SETTING_CRONTAB  /home/yi-hack/extra/script/conf2mqtt.sh camera" > /var/spool/cron/crontabs/root
    fi
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
