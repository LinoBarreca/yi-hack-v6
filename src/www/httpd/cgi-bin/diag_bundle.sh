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

# 6.0.1
#
# diag_bundle.sh - stream a diagnostics bundle (tar.gz) with everything useful
# for troubleshooting: boot log, service logs, kernel/process/network state and
# the configuration tree. SECRETS ARE REDACTED: any PASSWORD/PASS/PSK/secret
# value in the configs is replaced before packing (the bundle is meant to be
# attached to bug reports).

LOGDIR="/home/yi-hack/output/log"
CONFDIR="/home/yi-hack/config"
# "busybox mktemp": the applet is in the payload busybox but the flash symlink
# farm may predate it - the explicit prefix works in both states.
T=$(busybox mktemp -d /tmp/diag.XXXXXX) || exit 1
trap 'rm -rf "$T"' EXIT

# --- state dumps ---
date                     > "$T/date.txt" 2>&1
uptime                   > "$T/uptime.txt" 2>&1
dmesg                    > "$T/dmesg.txt" 2>&1
ps w                     > "$T/ps.txt" 2>&1
free                     > "$T/free.txt" 2>&1
cat /proc/meminfo        > "$T/meminfo.txt" 2>&1
mount                    > "$T/mounts.txt" 2>&1
df -h                    > "$T/df.txt" 2>&1
ifconfig -a              > "$T/ifconfig.txt" 2>&1
route -n                 > "$T/route.txt" 2>&1
netstat -tuln            > "$T/netstat.txt" 2>&1
iwconfig wlan0           > "$T/iwconfig.txt" 2>&1
top -b -n 1              > "$T/top.txt" 2>&1
busybox pstree -p        > "$T/pstree.txt" 2>&1
cat /proc/modules        > "$T/modules.txt" 2>&1
cat /proc/mtd            > "$T/mtd.txt" 2>&1
# open files / mount holders: bounded, a wedged SMB1 mount must not hang the CGI
timeout 10 lsof                                        > "$T/lsof.txt" 2>&1
timeout 5 busybox fuser -m /tmp/sd /tmp/cifs-ro /tmp/cifs-rw > "$T/fuser_mounts.txt" 2>&1
for _p in rmm cloud rRTSPServer; do
    _pid=$(pidof "$_p") && busybox pmap $_pid >> "$T/pmap.txt" 2>&1
done
cat /home/app/.camver    > "$T/model.txt" 2>&1
cat /home/yi-hack/version                > "$T/version_base.txt" 2>&1
cat /home/yi-hack/extra/../version       > "$T/version_payload.txt" 2>&1
readlink /home/yi-hack/extra             > "$T/firmware_source.txt" 2>&1
ls -lR /home/yi-hack/output              > "$T/output_view.txt" 2>&1

# --- logs ---
mkdir -p "$T/logs"
[ -e /dev/yi-boot.log ] && cat /dev/yi-boot.log > "$T/logs/yi-boot.log" 2>/dev/null
if [ -d "$LOGDIR" ]; then
    for f in "$LOGDIR"/*; do
        [ -f "$f" ] || continue
        [ "$(readlink "$f" 2>/dev/null)" = "/dev/null" ] && continue
        cp "$f" "$T/logs/" 2>/dev/null
    done
fi

# --- configuration, secrets redacted ---
mkdir -p "$T/config"
( cd "$CONFDIR" 2>/dev/null && find . -name '*.conf' -type f ) | while IFS= read -r f; do
    rel=${f#./}
    # mkdir only for files in subdirs: on "system.conf" ${rel%/*} is the whole
    # name and would create a DIRECTORY shadowing the file
    case "$rel" in */*) mkdir -p "$T/config/${rel%/*}" 2>/dev/null ;; esac
    sed -E 's/^([A-Z_]*(PASSWORD|PASS|PSK|SECRET)[A-Z_]*)=.+/\1=<redacted>/' \
        "$CONFDIR/$rel" > "$T/config/$rel"
done

FILENAME="diag-$(hostname)-$(date +%Y%m%d-%H%M%S).tar.gz"
printf "Content-type: application/gzip\r\n"
printf "Content-Disposition: attachment; filename=\"%s\"\r\n" "$FILENAME"
printf "\r\n"
tar -C "$T" -czf - .
