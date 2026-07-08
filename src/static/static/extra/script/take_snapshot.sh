#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# take_snapshot.sh - take one snapshot honoring config/services/snapshot.conf
# (RESOLUTION high|low, WATERMARK yes|no) and write the JPEG to stdout.
#
# Used by mqttv4 for the motion/event snapshot (MQTTV4_SNAPSHOT). Replaces the
# old hardcoded `imggrabber -r low -w`, which ignored the config. The web CGI
# snapshot.sh keeps its own per-request query params instead of this wrapper.

CONFIG_DIR="${CONFIG_DIR:-/home/yi-hack/config}"
. /home/yi-hack/base/script/get_config.sh

MOD=$(cat /home/app/.camver 2>/dev/null)

RES=$(get_config services.snapshot.RESOLUTION)
[ "$RES" = "low" ] || RES=high     # anything but an explicit "low" -> high

WM=""
[ "$(get_config services.snapshot.WATERMARK)" = "yes" ] && WM="-w"

exec /home/yi-hack/extra/bin/imggrabber -m "$MOD" -r "$RES" $WM
