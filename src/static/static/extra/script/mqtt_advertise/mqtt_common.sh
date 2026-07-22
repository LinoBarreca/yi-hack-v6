#!/bin/sh

#
#  This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
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
# mqtt_common.sh - shared plumbing for the mqtt_advertise scripts (they run
# from crontab, so this is a recurring path: every fork costs ~50-70ms on this
# CPU and everything here is shell builtins). Source get_config.sh first, then
# this file, then call:
#
#   mqtt_load_broker  -> sets HOSTNAME, MQTT_PREFIX and HOST (the broker plus
#                        optional ' -p PORT' / ' -u USER -P PASSWORD' words;
#                        pass $HOST to mosquitto_pub UNQUOTED, it must split)
#   mqtt_flags <retain> <qos>
#                     -> sets RETAIN ("-r" or "") and QOS ("-q N" or "")

mqtt_load_broker() {
    read HOSTNAME < /proc/sys/kernel/hostname
    BROKER_IP=""; BROKER_PORT=""; BROKER_USER=""; BROKER_PASSWORD=""
    load_config services.mqtt BROKER_IP BROKER_PORT BROKER_USER BROKER_PASSWORD
    HOST=$BROKER_IP
    if [ ! -z $BROKER_PORT ]; then
        HOST=$HOST' -p '$BROKER_PORT
    fi
    if [ ! -z $BROKER_USER ]; then
        HOST=$HOST' -u '$BROKER_USER' -P '$BROKER_PASSWORD
    fi
    load_config identity MQTT_PREFIX
}

mqtt_flags() {
    if [ "$1" == "1" ]; then
        RETAIN="-r"
    else
        RETAIN=""
    fi
    case "$2" in
        0|1|2) QOS="-q $2" ;;
        *)     QOS="" ;;
    esac
}
