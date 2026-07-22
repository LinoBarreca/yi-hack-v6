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

# 6.0.1 - yi-hack-v6
#
# env.sh - SINGLE SOURCE of the yi-hack process environment: PATH (incl. the
# farm-first busybox flip below), LD_LIBRARY_PATH, get_config, TZ.
# Sourced by /etc/profile (login shells: SSH/telnet) and by extra/script/system.sh
# (service tree - every daemon/CGI/cron job inherits from it). Do NOT duplicate
# this block elsewhere: it drifted three ways before being wired as the source.

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

# Fork-free read: env.sh is sourced by every login shell and every service
# script, so a get_config subshell here (3 forks ≈ 200ms) taxes each of them.
TIMEZONE=""
load_config system TIMEZONE
if [ ! -z "$TIMEZONE" ]; then
    export TZ=$TIMEZONE
fi
