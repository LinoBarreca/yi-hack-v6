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
# take_snapshot.sh - take one snapshot honoring config/services/snapshot.conf
# (ENABLED no|legacy|v6, RESOLUTION high|low, WATERMARK yes|no) and write the
# JPEG to stdout.
#
# Used by mqttv4 for the motion/event snapshot (MQTTV4_SNAPSHOT). The web CGI
# snapshot.sh keeps its own per-request query params instead of this wrapper.

CONFIG_DIR="${CONFIG_DIR:-/home/yi-hack/config}"
. /home/yi-hack/base/script/get_config.sh

MOD=$(cat /home/app/.camver 2>/dev/null)

RES=$(get_config services.snapshot.RESOLUTION)
[ "$RES" = "low" ] || RES=high     # anything but an explicit "low" -> high

MODE=$(get_config services.snapshot.ENABLED)
WM=$(get_config services.snapshot.WATERMARK)

if [ "$MODE" = "v6" ]; then
    [ "$RES" = "low" ] && CHN=3 || CHN=2
    # The snap channel is shared with rmm (cloud/app snapshots use it too): a
    # concurrent request can steal our frame -- retry once (hwsnap.c's own
    # comment). Every hwsnap failure path exits before writing any stdout
    # bytes, so retrying after a nonzero exit can't duplicate/corrupt output.
    if [ "$WM" = "yes" ]; then
        { /home/yi-hack/extra/bin/hwsnap -c "$CHN" || /home/yi-hack/extra/bin/hwsnap -c "$CHN"; } | /home/yi-hack/extra/bin/watermark
    else
        /home/yi-hack/extra/bin/hwsnap -c "$CHN" || /home/yi-hack/extra/bin/hwsnap -c "$CHN"
    fi
else
    # "legacy" and any other/unset value (incl. the pre-3-way "yes") fall
    # through here, so an existing on-flash config keeps working unchanged.
    if [ "$WM" = "yes" ]; then
        /home/yi-hack/extra/bin/imggrabber -m "$MOD" -r "$RES" | /home/yi-hack/extra/bin/watermark
    else
        exec /home/yi-hack/extra/bin/imggrabber -m "$MOD" -r "$RES"
    fi
fi
