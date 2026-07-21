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
# record.sh - native MP4 recorder. Remux the local RTSP stream (H264, plus AAC
# audio when enabled) into segmented MP4 files on the output/record view
# (output.RECORD matrix: RAM/SD/CIFS). "-c copy" means NO transcode, so CPU cost
# is negligible on the Hi3518e. This is the privacy-safe alternative to the stock
# mp4record (SD-fixed, cloud-coupled, leaks the WiFi PSK in its diagnostics).
#
# The file layout matches stock mp4record - hour dir YYYY'Y'MM'M'DD'D'HH'H',
# file MM'M'SS'S'.mp4 - so clean_records, ftppush, mqttv4 and the events web UI
# all recognise the recordings.
#
# Runs in the foreground (execs ffmpeg). wd_record.sh (re)launches and supervises
# it, and keeps the hour directories created (the segment muxer has no
# strftime_mkdir option).

. /home/yi-hack/base/script/get_config.sh

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:/lib:/home/lib"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"

REC_DIR="/home/yi-hack/output/record"
[ -d "$REC_DIR" ] || exit 0        # no view -> RECORD=NO or destination unavailable

RTSP_PORT=$(get_config services.rtsp.PORT)
[ -z "$RTSP_PORT" ] && RTSP_PORT=554
RTSP_USER=$(get_config services.rtsp.USER)
RTSP_PASSWORD=$(get_config services.rtsp.PASSWORD)
STREAM=$(get_config services.rtsp.STREAM)
AUDIO=$(get_config services.rtsp.AUDIO)

# high/both -> main stream ch0_0 ; low -> sub stream ch0_1
if [ "$STREAM" = "low" ]; then CH="ch0_1.h264"; else CH="ch0_0.h264"; fi

if [ -n "$RTSP_USER" ]; then AUTH="${RTSP_USER}:${RTSP_PASSWORD}@"; else AUTH=""; fi
URL="rtsp://${AUTH}127.0.0.1:${RTSP_PORT}/${CH}"

# Only AAC audio can be stream-copied into MP4; g711/pcm would break the muxer.
# The audio grabber only runs (and the RTSP stream only carries AAC) when AUDIO
# is enabled ("yes"; "aac" accepted too), so include audio only then, else
# record video-only.
if [ "$AUDIO" = "yes" ] || [ "$AUDIO" = "aac" ]; then MAP="-map 0"; else MAP="-map 0:v:0"; fi

SEG=$(get_config recording.SEGMENT_TIME)
case "$SEG" in ''|*[!0-9]*) SEG=60 ;; esac

# Create the current hour dir before ffmpeg opens the first segment (the segment
# muxer cannot mkdir); wd_record.sh keeps the current+next hour dirs ready.
mkdir -p "$REC_DIR/$(date +%YY%mM%dD%HH)"

exec ffmpeg -nostdin -loglevel error \
    -rtsp_transport tcp -i "$URL" \
    $MAP -c copy -f segment -segment_time "$SEG" -segment_atclocktime 1 \
    -reset_timestamps 1 -strftime 1 \
    "$REC_DIR/%YY%mM%dD%HH/%MM%SS.mp4"
