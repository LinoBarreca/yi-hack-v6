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

# Motion-only recording (recording.MOTION_ONLY=yes). The recorder always
# writes continuous segments; once a segment is finished and its post-roll has
# passed, delete it unless there was motion within it or MOTION_MARGIN seconds
# either side - so what stays is each event with pre- and post-roll. Motion
# times come from MOTION_SEEN (its mtime is the last moment of motion, touched
# by campipe's detector), sampled every pass into MOTION_TIMES. Only segments
# that ended while we were watching are judged: after a reboot the motion
# history is gone, and older recordings are left alone rather than deleted on
# no evidence. Native pipeline only: in stock mode nothing touches
# MOTION_SEEN, so every segment would look motionless. With MOTION_ONLY=no
# nothing is deleted (continuous).
MOTION_SEEN="/tmp/ipc/motion_seen"
MOTION_TIMES="/tmp/rec_motion_times"
MOTION_MARGIN=15
SEG_TIME=""
load_config recording SEGMENT_TIME
SEG_TIME=$SEGMENT_TIME
case "$SEG_TIME" in ''|*[!0-9]*) SEG_TIME=60 ;; esac
WATCH_SINCE=$(date +%s)
LAST_SEEN=""
: > "$MOTION_TIMES"

had_motion()   # $1 = from, $2 = to (epoch)
{
    while read -r t; do
        [ "$t" -ge "$1" ] && [ "$t" -le "$2" ] && return 0
    done < "$MOTION_TIMES"
    return 1
}

prune_record()
{
    local now seen f end
    [ -d "$REC_DIR" ] || return
    pidof campipe > /dev/null || return
    now=$(date +%s)
    # we start before NTP: watch only from the first pass with a real clock
    if [ "$WATCH_SINCE" -lt 1600000000 ]; then
        [ "$now" -ge 1600000000 ] && WATCH_SINCE=$now
        return
    fi

    if [ -f "$MOTION_SEEN" ]; then
        seen=$(stat -c %Y "$MOTION_SEEN")
        # continuous motion still leaves a sample every pass (INTERVAL), well
        # inside the segment length, so no segment with motion is missed
        if [ "$seen" != "$LAST_SEEN" ]; then
            echo "$seen" >> "$MOTION_TIMES"
            LAST_SEEN=$seen
        fi
    fi
    # keep two hours of history
    awk -v t=$(( now - 7200 )) '$1 >= t' "$MOTION_TIMES" > "$MOTION_TIMES.tmp" && \
        mv "$MOTION_TIMES.tmp" "$MOTION_TIMES"

    # re-read every pass: the web UI changes it without restarting us
    MOTION_ONLY=""
    load_config recording MOTION_ONLY 2>/dev/null
    [ "$MOTION_ONLY" = "yes" ] || return

    # trailing slash: REC_DIR is a symlink to the destination, which find
    # would not descend into otherwise
    for f in $(find "$REC_DIR/" -name '*.mp4' -mmin -15 2>/dev/null); do
        end=$(stat -c %Y "$f")
        # still being written, post-roll not over yet, or ended before we watched
        [ $(( now - end )) -lt $(( MOTION_MARGIN + 5 )) ] && continue
        [ "$end" -lt $(( WATCH_SINCE + MOTION_MARGIN )) ] && continue
        had_motion $(( end - SEG_TIME - MOTION_MARGIN )) $(( end + MOTION_MARGIN )) && continue
        rm -f "$f"
    done
}

# A recorder that runs but writes nothing (stream stalled) would never be
# restarted by the pidof check alone: kill it once no segment has been touched
# for two segment lengths, and the check below starts a fresh one.
check_stalled()
{
    local newest
    pidof ffmpeg > /dev/null || return
    newest=$(find "$REC_DIR/" -name '*.mp4' -mmin -$(( (2 * SEG_TIME + 59) / 60 )) 2>/dev/null | head -n 1)
    [ -n "$newest" ] && return
    [ $(( $(date +%s) - WATCH_SINCE )) -lt $(( 2 * SEG_TIME )) ] && return
    echo "$(date +'%Y-%m-%d %H:%M:%S') - recorder stalled (no segment for $(( 2 * SEG_TIME ))s), restarting ..." >> "$LOG_FILE"
    killall -9 ffmpeg
    sleep 1
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
    check_stalled
    check_record
    prune_record
    sleep $INTERVAL
done
