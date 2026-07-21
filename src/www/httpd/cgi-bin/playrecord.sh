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
# Stream a recorded mp4 from the output/record view. Used instead of a static
# /record URL because recordings live on the output matrix destination
# (RAM/SD/CIFS), not under the web root - and the web root (extra/www) may be a
# read-only CIFS mount where a /record symlink can't be created.
#
# QUERY_STRING: dir=<hour dir>&file=<mp4>

REC_DIR="/home/yi-hack/output/record"

# Only allow the expected characters in the whole query (blocks path traversal).
case $QUERY_STRING in
    *[!a-zA-Z0-9=\&_.-]* ) exit ;;
esac

DIR=""
FILE=""
OIFS=$IFS; IFS='&'; set -- $QUERY_STRING; IFS=$OIFS
for kv in "$@"; do
    k=${kv%%=*}
    v=${kv#*=}
    [ "$k" = "dir" ] && DIR="$v"
    [ "$k" = "file" ] && FILE="$v"
done

# dir = "YYYY'Y'MM'M'DD'D'HH'H'" (14, alnum) ; file = "MM'M'SS'S'.mp4" (10)
case "$DIR" in ""|*[!0-9A-Za-z]* ) exit ;; esac
case "$FILE" in ""|*[!0-9A-Za-z.]* ) exit ;; esac
[ ${#DIR} -eq 14 ] || exit
[ ${#FILE} -eq 10 ] || exit

TARGET="$REC_DIR/$DIR/$FILE"
[ -f "$TARGET" ] || exit

printf "Content-type: video/mp4\r\nContent-Disposition: inline; filename=\"%s\"\r\n\r\n" "$FILE"
cat "$TARGET"
