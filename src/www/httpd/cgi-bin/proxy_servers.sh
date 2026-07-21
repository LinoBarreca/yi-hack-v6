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

# 6.0.1
#
# proxy_servers.sh - report the proxy server list currently configured in
# config/services/proxychains.conf. The file is always written by set_configs.sh
# as <template> + one server per line, so the server lines are simply everything
# past the template length. Output: {"servers":"line1;line2;..."}

CONF=/home/yi-hack/config/services/proxychains.conf
TPL=$CONF.template

printf "Content-type: application/json\r\n\r\n"

if [ ! -f "$CONF" ] || [ ! -f "$TPL" ]; then
    printf '{"servers":""}'
    exit 0
fi

TPL_LINES=$(grep -c "" "$TPL")

printf '{"servers":"'
sed "1,${TPL_LINES}d" "$CONF" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    # escape for JSON; ';' is the list separator used by PROXYCHAINS_SERVERS
    esc=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/;/ /g')
    [ "$FIRSTDONE" = 1 ] && printf ';'
    printf '%s' "$esc"
    FIRSTDONE=1
done
printf '"}'
