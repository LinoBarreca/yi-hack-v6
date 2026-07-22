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

validateFile()
{
    case $1 in
        *[\'!\"@\#\$%\&^*\(\),:\;]* )
            echo "invalid";;
        *)
            echo $1;;
    esac
}

CONFIG_DIR="${CONFIG_DIR:-/home/yi-hack/config}"

fail503()
{
    printf "Status: 503 Service Unavailable\r\n"
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
    exit 0
}

# This CGI is the live-view hot path (the viewer chains one request per frame), so
# read both config values inline with builtins instead of forking grep / sourcing
# get_config.sh - each fork costs ~50-70ms on this CPU and dominated the latency
# once v6/hwsnap made the capture itself fast (~40ms).

# Global camera switch (camera.conf SWITCH_ON=no -> camera off).
while IFS='=' read -r K V; do
    [ "$K" = "SWITCH_ON" ] && [ "$V" = "no" ] && fail503
done < "$CONFIG_DIR/camera.conf"

# Snapshot backend (services/snapshot.conf ENABLED): no | legacy | v6.
MODE=legacy
while IFS='=' read -r K V; do
    [ "$K" = "ENABLED" ] && MODE=$V
done < "$CONFIG_DIR/services/snapshot.conf"
[ "$MODE" = "no" ] && fail503

read MODEL_SUFFIX < /home/app/.camver
BASE64="no"
RES="high"
WATERMARK="no"
OUTPUT_FILE="none"

# Parse QUERY_STRING with pure parameter expansion (no echo|cut subshells). The
# old cut-based loop spawned ~24 processes per request (~1.4s on this CPU) - it
# dominated the whole snapshot latency once v6/hwsnap made the capture itself fast.
OIFS=$IFS
IFS='&'
for PAIR in $QUERY_STRING ; do
    KEY=${PAIR%%=*}
    VAL=${PAIR#*=}
    case "$KEY" in
        res)       RES=$VAL ;;
        watermark) WATERMARK=$VAL ;;
        base64)    BASE64=$VAL ;;
        file)      OUTPUT_FILE=$VAL ;;
    esac
done
IFS=$OIFS
[ "$RES" = "low" ] || RES=high    # anything but an explicit "low" -> high

REDIRECT=""
if [ "$OUTPUT_FILE" != "none" ] ; then
    OUTPUT_FILE=$(validateFile "$OUTPUT_FILE")
    if [ "$OUTPUT_FILE" != "invalid" ]; then
        OUTPUT_DIR=$(cd "$(dirname "/tmp/sd/record/$OUTPUT_FILE")"; pwd)
        OUTPUT_DIR=${OUTPUT_DIR:0:14}
        if [ "$OUTPUT_DIR" == "/tmp/sd/record" ]; then
            REDIRECT="yes"
        fi
    fi
fi

# capture: write one raw JPEG to stdout, imggrabber (legacy) or hwsnap (v6) per
# services.snapshot.ENABLED. snapshot: capture, optionally piped through
# watermark per services.snapshot.WATERMARK (the query param, not the config file).
capture()
{
    if [ "$MODE" == "v6" ] ; then
        [ "$RES" == "low" ] && CHN=3 || CHN=2
        # Snap channel is shared with rmm: a concurrent request can steal our
        # frame -- retry once (hwsnap.c's own comment). Every hwsnap failure
        # path exits before writing any stdout bytes, so this can't corrupt output.
        hwsnap -c "$CHN" || hwsnap -c "$CHN"
    else
        imggrabber -m $MODEL_SUFFIX -r $RES
    fi
}

if [ "$WATERMARK" == "yes" ] ; then
    snapshot() { capture | watermark; }
else
    snapshot() { capture; }
fi

if [ "$REDIRECT" == "yes" ] ; then
    if [ "$BASE64" == "no" ] ; then
        snapshot > /tmp/sd/record/$OUTPUT_FILE
    elif [ "$BASE64" == "yes" ] ; then
        snapshot | base64 > /tmp/sd/record/$OUTPUT_FILE
    fi
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "false"
    printf "}"
else
    if [ "$BASE64" == "no" ] ; then
        printf "Content-type: image/jpeg\r\n\r\n"
        snapshot
    elif [ "$BASE64" == "yes" ] ; then
        printf "Content-type: image/jpeg;base64\r\n\r\n"
        snapshot | base64
    fi
fi
