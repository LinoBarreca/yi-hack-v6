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
# wd_record.sh - launch and supervise the native MP4 recorder (record.sh), and
# pre-create the hour directories it writes into. ffmpeg's segment muxer has no
# strftime_mkdir option, so the hour dir must exist before the segment for that
# hour is opened; we create the current AND next hour every tick so the rollover
# at the top of the hour never races.

script_name=$(basename -- "$0")
if pidof "$script_name" -o $$ >/dev/null; then
    echo "Already Running - Quitting"
    exit 1
fi

. /home/yi-hack/base/script/get_config.sh

REC_DIR="/home/yi-hack/output/record"
# Routed through the output/log view (output.LOG matrix); on NO the view symlinks
# this to /dev/null.
LOG_FILE="/home/yi-hack/output/log/wd_record.log"
INTERVAL=20

# Nothing to record if the matrix says NO (no view) or the RTSP source is off.
RECORD=""; ENABLED=""
load_config output RECORD
load_config services.rtsp ENABLED
[ "$RECORD" = "NO" ] && exit 0
[ "$ENABLED" = "yes" ] || exit 0

ensure_dirs()
{
    [ -d "$REC_DIR" ] || return
    mkdir -p "$REC_DIR/$(date +%YY%mM%dD%HH)"
    mkdir -p "$REC_DIR/$(date -d @$(( $(date +%s) + 3600 )) +%YY%mM%dD%HH)"
}

check_record()
{
    if ! pidof ffmpeg > /dev/null; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - recorder not running, starting record.sh ..." >> "$LOG_FILE"
        /home/yi-hack/extra/script/record.sh &
    fi
}

echo "$(date +'%Y-%m-%d %H:%M:%S') - Starting record watchdog..." >> "$LOG_FILE"

while true
do
    ensure_dirs
    check_record
    sleep $INTERVAL
done
