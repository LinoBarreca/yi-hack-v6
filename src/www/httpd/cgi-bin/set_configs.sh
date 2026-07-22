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
#
# set_configs.sh - write config keys posted by the web UI.
#
# Body format: one "KEY=url-encoded-value" per line (built by api.setConf in
# ui/app.js - we control both ends). The previous JSON body needed jq, which
# takes ~12 SECONDS per invocation on this CPU: two jq runs made every save
# take half a minute. Plain line parsing is instant and handles any character
# via the url-encoding.
#
# Flash wear: a key whose value is unchanged is skipped entirely (no sed, no
# jffs2 rewrite) - most saves change one or two keys out of many posted.

get_conf_type()
{
    if [ "${QUERY_STRING%%=*}" == "conf" ] ; then
        echo "${QUERY_STRING#*=}"
    fi
}

# %XX -> byte (encodeURIComponent never emits '+', so no '+' handling needed).
urldecode() { printf '%b' "${1//%/\\x}"; }

fail() {
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n\"error\":\"true\"\n}"
    exit 0
}

. /home/yi-hack/www/cgi-bin/validate.sh
$(validateQueryString $QUERY_STRING) || fail

CONF_TYPE="$(get_conf_type)"
[ -n "$CONF_TYPE" ] || fail

# Per-service config files live under config/services/; the rest (system,
# recording, camera, identity, output) at config/ top level.
case "$CONF_TYPE" in
    snapshot|httpd|rtsp|onvif|telnetd|sshd|ftpd|ftp_upload|ntpd|proxychains|mqtt|mqtt_advertise)
        CONF_FILE="/home/yi-hack/config/services/$CONF_TYPE.conf"
        CONF_SECTION="services.$CONF_TYPE" ;;
    *)
        CONF_FILE="/home/yi-hack/config/$CONF_TYPE.conf"
        CONF_SECTION="$CONF_TYPE" ;;
esac

# Build-time locked settings (config/locked.conf) cannot be changed from the UI.
. /home/yi-hack/base/script/locked_conf.sh

# "|| [ -n "$ROW" ]": keep the last line even when the body has no trailing
# newline (read returns non-zero at EOF but still fills the variable).
while IFS= read -r ROW || [ -n "$ROW" ]; do
    [ -n "$ROW" ] || continue
    case "$ROW" in *=*) ;; *) continue ;; esac
    KEY=${ROW%%=*}
    # keys are plain identifiers; refuse anything else (defense in depth)
    case "$KEY" in *[!A-Z0-9_]*|"") continue ;; esac
    VALUE=$(urldecode "${ROW#*=}")
    # the config files are line-based: a value can never contain a newline
    VALUE=$(printf '%s' "$VALUE" | tr -d '\n\r')

    if is_locked "$CONF_SECTION.$KEY" ; then
        continue
    fi

    if [ "$KEY" == "HOSTNAME" ] ; then
        if [ -z "$VALUE" ] ; then
            # Use 2 last MAC address numbers to set a different hostname
            MAC=$(awk -F: '{print $5 $6}' /sys/class/net/wlan0/address)
            if [ "$MAC" != "" ]; then
                hostname yi-$MAC
            else
                hostname yi-hack-v6
            fi
            hostname > /home/yi-hack/config/hostname
        else
            hostname "$VALUE"
            echo "$VALUE" > /home/yi-hack/config/hostname
        fi
        continue
    fi

    if [ "$KEY" == "PROXYCHAINS_SERVERS" ] ; then
        # value = ';'-separated proxy lines appended to the template
        cat $CONF_FILE.template > $CONF_FILE
        printf '%s\n' "$VALUE" | tr ';' '\n' >> $CONF_FILE
        continue
    fi

    if [ "$KEY" == "MOTION_IMAGE_DELAY" ] ; then
        $(validateNumber $VALUE) || continue
        VALUE=${VALUE//,/.}
        [ "$(awk 'BEGIN{ print "'$VALUE'"<="'5.0'" }')" == "1" ] || continue
    fi

    # Skip untouched keys: no flash write, no /etc/TZ write.
    # Not suppressed: an unreadable conf file makes CUR empty for every key,
    # which defeats the skip-untouched test below and rewrites flash needlessly.
    CUR=$(sed -n "/^${KEY}[[:blank:]]*=/{s/^[^=]*=//;p;q}" "$CONF_FILE")
    [ "$CUR" == "$VALUE" ] && continue

    if [ "$KEY" == "TIMEZONE" ] ; then
        echo "$VALUE" > /etc/TZ
    fi
    EV=$(printf '%s' "$VALUE" | sed 's/[|&\\]/\\&/g')
    sed -i "s|^\(${KEY}[[:blank:]]*=[[:blank:]]*\).*$|\1${EV}|" $CONF_FILE
done

printf "Content-type: application/json\r\n\r\n"
printf "{\n\"error\":\"false\"\n}"
