#!/bin/sh

# 0.1.0



export LD_LIBRARY_PATH=/lib:/usr/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib:/home/yi-hack/extra/lib:/home/yi-hack/extra/lib
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/home/base/tools:/home/yi-hack/extra/bin:/home/app/localbin:/home/base:/home/yi-hack/extra/bin:/home/yi-hack/extra/sbin:/home/yi-hack/extra/usr/bin:/home/yi-hack/extra/usr/sbin:/home/yi-hack/extra/sbin

. /home/yi-hack/base/script/get_config.sh

TZ_CONF=$(get_config system.TIMEZONE)

if [ ! -z "$TZ_CONF" ]; then
    export TZ=$TZ_CONF
fi
