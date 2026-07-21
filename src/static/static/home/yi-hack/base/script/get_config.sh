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
# Centralized config reader. Source this file (". get_config.sh") to define
# get_config(). Replaces the ~10 duplicated, buggy local definitions of v5.
#
# Usage:   get_config <path>.<KEY>
# Example: get_config services.rtsp.PORT  -> reads config/services/rtsp.conf key PORT
#          get_config system.TIMEZONE     -> reads config/system.conf       key TIMEZONE
#
# The argument is split on the LAST dot: everything after is the KEY, everything
# before is the file path (remaining dots become "/"). Keys are UPPERCASE and
# never contain dots, so the split is unambiguous.
#
# Config lives in flash at the fixed logical path /home/yi-hack/config (the logical view).
# CONFIG_DIR can still be overridden by the caller before sourcing.
: "${CONFIG_DIR:=/home/yi-hack/config}"

get_config() {
    _gc_key=${1##*.}                              # after last dot
    _gc_path=${1%.*}                              # before last dot
    _gc_file="$CONFIG_DIR/${_gc_path//./\/}.conf" # remaining dots -> slashes

    # A missing file here means a typo/unknown section, or a known file deleted
    # before check_conf re-seeded it (see check_conf.sh base/extra). The path in
    # the message tells which: an unknown service -> bug; a known file -> state.
    if [ ! -f "$_gc_file" ]; then
        echo "get_config[ERROR]: file $_gc_file not found (key $1)" >&2
        return 1
    fi

    # ^KEY= anchored (no spurious substring match); cut -f2- preserves '=' in values (passwords).
    # A missing key (vs an empty value, which is legitimate and silent) usually
    # means a caller was not migrated to the new key name.
    if ! grep -qE "^${_gc_key}=" "$_gc_file"; then
        echo "get_config[ERROR]: key $_gc_key not found in $_gc_file" >&2
        return 1
    fi

    # First match only (q); strip up to the first '=' so '=' in values (passwords) survives.
    sed -n "/^${_gc_key}=/{s/^[^=]*=//;p;q}" "$_gc_file"
}
