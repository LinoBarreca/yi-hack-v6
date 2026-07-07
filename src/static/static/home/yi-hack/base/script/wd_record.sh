#!/bin/sh

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
[ "$(get_config output.RECORD)" = "NO" ] && exit 0
[ "$(get_config services.rtsp.ENABLED)" = "yes" ] || exit 0

ensure_dirs()
{
    [ -d "$REC_DIR" ] || return
    mkdir -p "$REC_DIR/$(date +%YY%mM%dD%HH)"
    mkdir -p "$REC_DIR/$(date -d @$(( $(date +%s) + 3600 )) +%YY%mM%dD%HH)"
}

check_record()
{
    if [ "$(ps | grep -w ffmpeg | grep -v grep | grep -c ^)" -eq 0 ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - recorder not running, starting record.sh ..." >> "$LOG_FILE"
        /home/yi-hack/base/script/record.sh &
    fi
}

echo "$(date +'%Y-%m-%d %H:%M:%S') - Starting record watchdog..." >> "$LOG_FILE"

while true
do
    ensure_dirs
    check_record
    sleep $INTERVAL
done
