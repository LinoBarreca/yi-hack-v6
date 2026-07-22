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

# 6.0.1

CONF_FILE="/home/yi-hack/config/camera.conf"

# Build-time locked settings (config/locked.conf) cannot be changed from the UI.
. /home/yi-hack/base/script/locked_conf.sh

# Parse QUERY_STRING with parameter expansion (no echo|cut subshells - the old
# fixed 1..9 cut loop forked ~4x per slot, ~50-70ms per fork on this CPU).
OIFS=$IFS
IFS='&'
for PAIR in $QUERY_STRING ; do
    CONF=${PAIR%%=*}
    VAL=${PAIR#*=}
    [ -n "$CONF" ] || continue

    # locked.conf keys are UPPERCASE (busybox ash has no ${VAR^^}; tr is one
    # fork per submitted key, acceptable on this user-triggered path).
    if is_locked "camera.$(echo "$CONF" | tr 'a-z' 'A-Z')" ; then
        continue
    fi

    case "$CONF" in
        switch_on)
            if [ "$VAL" = "no" ] ; then
                ipc_cmd -t off
                sleep 1
                ipc_cmd -T  # Stop current motion detection event
            else
                ipc_cmd -t on
            fi ;;
        save_video_on_motion)
            if [ "$VAL" = "no" ] ; then
                ipc_cmd -v always
            else
                ipc_cmd -v detect
            fi ;;
        sensitivity)
            ipc_cmd -s "$VAL" ;;
        sound_detection)
            if [ "$VAL" = "no" ] ; then
                ipc_cmd -b off
            else
                ipc_cmd -b on
            fi ;;
        sound_sensitivity)
            case "$VAL" in
                50|60|70|80|90) ipc_cmd -n "$VAL" ;;
            esac ;;
        baby_crying_detect)
            if [ "$VAL" = "no" ] ; then
                ipc_cmd -B off
            else
                ipc_cmd -B on
            fi ;;
        led)
            if [ "$VAL" = "no" ] ; then
                ipc_cmd -l off
            else
                ipc_cmd -l on
            fi ;;
        ir)
            if [ "$VAL" = "no" ] ; then
                ipc_cmd -i off
            else
                ipc_cmd -i on
            fi ;;
        mic)
            if [ "$VAL" = "no" ] ; then
                ipc_cmd -I off
            else
                ipc_cmd -I on
            fi ;;
        rotate)
            if [ "$VAL" = "no" ] ; then
                ipc_cmd -r off
            else
                ipc_cmd -r on
            fi ;;
        # Settings below were only settable via MQTT cmnd/ before; flags match
        # the validate.c table (mqtt-config), one source of truth for the mapping.
        motion_detection)     ipc_cmd -O "$VAL" ;;
        ai_human_detection)   ipc_cmd -a "$VAL" ;;
        ai_vehicle_detection) ipc_cmd -E "$VAL" ;;
        ai_animal_detection)  ipc_cmd -N "$VAL" ;;
        face_detection)       ipc_cmd -c "$VAL" ;;
        motion_tracking)      ipc_cmd -o "$VAL" ;;
        cruise)               ipc_cmd -C "$VAL" ;;
        *) continue ;;   # unknown key: no ipc_cmd sent, no settle sleep needed
    esac
    sleep 1   # let the stock app settle between consecutive ipc_cmd settings
done
IFS=$OIFS

printf "Content-type: application/json\r\n\r\n"

printf "{\n"
printf "\"%s\":\"%s\"\\n" "error" "false"
printf "}"
