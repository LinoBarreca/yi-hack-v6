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

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:$LD_LIBRARY_PATH"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"
MOSQUITTO_PUB="/home/yi-hack/extra/bin/mosquitto_pub"

. /home/yi-hack/base/script/get_config.sh
. /home/yi-hack/extra/script/mqtt_advertise/mqtt_common.sh

CONTENT=$(/home/yi-hack/www/cgi-bin/links.sh | sed 1d | tr -d '\n')

# MQTT configuration (batch fork-free reads; see mqtt_common.sh)
mqtt_load_broker
LINK_TOPIC=""; LINK_RETAIN=""; LINK_QOS=""
load_config services.mqtt_advertise LINK_TOPIC LINK_RETAIN LINK_QOS
mqtt_flags "$LINK_RETAIN" "$LINK_QOS"
TOPIC=$MQTT_PREFIX/$LINK_TOPIC

$MOSQUITTO_PUB -i $HOSTNAME $QOS $RETAIN -h $HOST -t $TOPIC -m "$CONTENT"
