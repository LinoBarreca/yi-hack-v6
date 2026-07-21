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

# Helpers for the rescue CGI: read x-www-form-urlencoded POST, decode fields, write config keys.
CONFIG=/home/yi-hack/config

read_body() { read -r BODY; }

# urldecode: '+' -> space, %XX -> byte
urldecode() { _d="${1//+/ }"; printf '%b' "${_d//%/\\x}"; }

# get_field NAME -> decoded value of NAME from $BODY (no eval; only known keys are queried)
get_field() { _v=$(printf '%s' "$BODY" | tr '&' '\n' | grep "^$1=" | head -n1); urldecode "${_v#*=}"; }

# setkey FILE KEY VALUE -> set KEY=VALUE in $CONFIG/FILE (update in place or append).
# Build-time locked settings (config/locked.conf) are refused, rescue UI included.
. /home/yi-hack/base/script/locked_conf.sh
setkey() {
    _sec="${1%.conf}"; _sec="${_sec//\//.}"
    is_locked "$_sec.$2" && return 0
    _f="$CONFIG/$1"; touch "$_f"
    if grep -qE "^$2=" "$_f"; then
        _ev=$(printf '%s' "$3" | sed 's/[|&\\]/\\&/g')
        sed -i "s|^$2=.*|$2=$_ev|" "$_f"
    else
        printf '%s=%s\n' "$2" "$3" >> "$_f"
    fi
}
