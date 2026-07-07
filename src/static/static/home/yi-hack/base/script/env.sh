#!/bin/sh

# 6.0.1



export LD_LIBRARY_PATH=/lib:/usr/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib:/home/yi-hack/extra/lib:/home/yi-hack/base/lib

# PATH selects which busybox serves the applets, with NO flash writes and NO rootfs changes:
#  - extra mounted (full busybox present): base/bin first -> the flash farm (base/bin/<applet>
#    -> extra/bin/busybox) wins, so every applet + the patched httpd come from the full busybox;
#    extra/bin follows for the service binaries (pure-ftpd, rRTSPServer, ...).
#  - otherwise: the rootfs mini busybox wins (4 dirs); base/bin stays last only so dropbear
#    (real binaries living there) is reachable. Its applet symlinks dangle but are shadowed.
if [ -x /home/yi-hack/extra/bin/busybox ]; then
    export PATH=/home/yi-hack/base/bin:/home/yi-hack/extra/bin:/usr/bin:/usr/sbin:/bin:/sbin:/home/base/tools:/home/app/localbin:/home/base
else
    export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/home/base/tools:/home/app/localbin:/home/base:/home/yi-hack/base/bin
fi

. /home/yi-hack/base/script/get_config.sh

TZ_CONF=$(get_config system.TIMEZONE)

if [ ! -z "$TZ_CONF" ]; then
    export TZ=$TZ_CONF
fi
