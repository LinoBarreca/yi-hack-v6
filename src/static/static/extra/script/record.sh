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
. /home/yi-hack/extra/script/url_helpers.sh   # urlencode (credentialed URLs)

export LD_LIBRARY_PATH="/home/yi-hack/extra/lib:/home/yi-hack/base/lib:/lib:/home/lib"
export PATH="$PATH:/home/yi-hack/extra/bin:/bin:/usr/bin"

REC_DIR="/home/yi-hack/output/record"
[ -d "$REC_DIR" ] || exit 0        # no view -> RECORD=NO or destination unavailable

# Batch fork-free config read. Pre-clear USER: it is in the environment.
PORT=""; USER=""; PASSWORD=""; STREAM=""; AUDIO=""
load_config services.rtsp PORT USER PASSWORD STREAM AUDIO
RTSP_PORT=$PORT
[ -z "$RTSP_PORT" ] && RTSP_PORT=554
RTSP_USER=$USER
RTSP_PASSWORD=$PASSWORD
# STREAM is a generic key name used by BOTH services.rtsp and recording; rename it
# per-service immediately, before the recording load below reuses the variable.
RTSP_STREAM=$STREAM

# Which stream to record: recording.STREAM, NOT services.rtsp STREAM - the latter
# says what is published, and you may well want to serve 1080p while recording the
# small stream. Two things can override the request:
#
#  1. RTSP only publishes some channels: STREAM=high -> ch0_0 only, low -> ch0_1
#     only, both -> either. We cannot record what is not being served.
#  2. On y20, recording 1080p needs SWAP. ffmpeg buffering the main stream wants
#     ~11MB of anon memory on a board with ~30MB total and (with SWAP_FILE=NO)
#     nothing reclaimable - the page cache is CIFS-backed and pinned, so
#     MemAvailable sits at 0. Measured on y20: every 1080p attempt is OOM-killed
#     within seconds ("Killed process (ffmpeg) anon-rss:10992kB"), and wd_record.sh
#     restarts it forever, so the box just grinds. The low stream records fine.
#     This gate is deliberately scoped to y20: it is a MEASURED fact about that
#     board, not a known property of every model - others may have more RAM and we
#     have not tested them, so they are left alone rather than silently downgraded.
#     Add a model here only after measuring it. Within y20 the test is whether swap
#     is actually ACTIVE, not what the config key says, so a swapon that failed
#     (SD full, FAT rejected the file) degrades to low instead of OOM-looping.
STREAM=""; SEGMENT_TIME=""
load_config recording STREAM SEGMENT_TIME
REC_STREAM=$STREAM
case "$REC_STREAM" in high|low) : ;; *) REC_STREAM=low ;; esac

# What RTSP publishes constrains the choice.
case "$RTSP_STREAM" in
    low)  WANT=low ;;
    high) WANT=high ;;
    *)    WANT=$REC_STREAM ;;
esac
if [ "$WANT" != "$REC_STREAM" ]; then
    echo "record.sh: recording.STREAM=$REC_STREAM but rtsp publishes only $RTSP_STREAM - recording $WANT"
fi

# y20 only: 1080p without swap gets OOM-killed, so fall back rather than loop.
MODEL_SUFFIX=""; read MODEL_SUFFIX 2>/dev/null < /home/app/.camver
if [ "$WANT" = "high" ] && [ "$MODEL_SUFFIX" = "y20" ] && \
   ! grep -q "^/" /proc/swaps 2>/dev/null; then
    if [ "$RTSP_STREAM" = "high" ]; then
        echo "record.sh: WARNING 1080p recording on y20 needs swap (output.SWAP_FILE) and rtsp publishes only high - recording it anyway, expect OOM"
    else
        echo "record.sh: 1080p recording on y20 needs swap (output.SWAP_FILE=NO) - falling back to the low stream"
        WANT=low
    fi
fi

if [ "$WANT" = "low" ]; then CH="ch0_1.h264"; else CH="ch0_0.h264"; fi

# Percent-encode the credentials in the RTSP URL: ffmpeg parses the URL, so a
# password with URL-reserved chars (@ : ; $ ...) would otherwise break it.
if [ -n "$RTSP_USER" ]; then
    urlencode "$RTSP_USER" RTSP_USER_ENC
    urlencode "$RTSP_PASSWORD" RTSP_PWD_ENC
    AUTH="${RTSP_USER_ENC}:${RTSP_PWD_ENC}@"
else
    AUTH=""
fi
URL="rtsp://${AUTH}127.0.0.1:${RTSP_PORT}/${CH}"

# Only AAC audio can be stream-copied into MP4 (ffmpeg's mp4 muxer has no PCM
# entry at all - the 'ulaw' tag lives only in the mov table), so AUDIO=g711 records
# video-only, as does AUDIO=no. "yes" is the legacy spelling of "aac".
#
# Map the two tracks EXPLICITLY. `-map 0` would also pick up the ONVIF two-way
# backchannel, which the SDP advertises as a third stream (sendonly PCMU) on every
# native-pipeline model with a speaker: it carries no data to record, and ffmpeg
# aborts the whole recording on it ("codec frame size is not set") because mp4
# cannot hold u-law.
# Verified on hardware: with -map 0 and the backchannel on, ffmpeg exits rc=1 and
# writes nothing at all - video included.
#
# The '?' on the audio map makes it OPTIONAL, and it is not decoration: AUDIO says
# what is CONFIGURED, not what the stream actually carries. rRTSPServer drops the
# audio track whenever its FIFO is missing (campipe still starting, audio disabled
# in the running pipeline, stock mode without the audio grabber), and a mandatory
# map against a video-only stream makes ffmpeg exit rc=1 with "Stream map '0:a:0'
# matches no streams" - after which wd_record.sh relaunches it every 20s forever
# and NOTHING is recorded, video included. With '?' the same case simply records
# video-only, which is the intended degradation.
if [ "$AUDIO" = "yes" ] || [ "$AUDIO" = "aac" ]; then
    MAP="-map 0:v:0 -map 0:a:0?"
else
    MAP="-map 0:v:0"
fi

SEG=$SEGMENT_TIME
case "$SEG" in ''|*[!0-9]*) SEG=60 ;; esac

# Create the current hour dir before ffmpeg opens the first segment (the segment
# muxer cannot mkdir); wd_record.sh keeps the current+next hour dirs ready.
mkdir -p "$REC_DIR/$(date +%YY%mM%dD%HH)"

# -probesize: ffmpeg's default is 5 MB, which on this 30 MB box is enough to get
# the process OOM-killed before it writes a single segment (verified on hardware:
# "Out of memory: Kill process (ffmpeg) ... anon-rss:11316kB", triggered while the
# native pipeline was resident). 500 kB is ample to identify H.264 + AAC and keeps
# the footprint well inside what is actually free.
# -map_metadata -1: drop the RTSP session metadata instead of copying it into every
# clip. live555 advertises an SDP session description, so without this each MP4 ends
# up tagged title='Session streamed by "rRTSPServer"' and comment='ch0_1.h264', which
# is what players show as the clip title - an implementation detail with no business
# being in the user's recordings.
#
# $MAP is deliberately unquoted (it must split into separate arguments), so turn
# globbing off first: the '?' in "0:a:0?" is a wildcard to the shell, and a stray
# file matching it in the cwd would silently rewrite the argument. Nothing below
# needs pathname expansion, and it costs no fork.
set -f
exec ffmpeg -nostdin -loglevel error -probesize 500k \
    -rtsp_transport tcp -i "$URL" \
    $MAP -c copy -map_metadata -1 -f segment -segment_time "$SEG" -segment_atclocktime 1 \
    -reset_timestamps 1 -strftime 1 \
    "$REC_DIR/%YY%mM%dD%HH/%MM%SS.mp4"
