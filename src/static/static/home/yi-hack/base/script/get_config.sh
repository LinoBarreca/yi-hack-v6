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
# get_config() and load_config(). Replaces the ~10 duplicated, buggy local
# definitions of v5.
#
# Usage:   get_config <path>.<KEY>
# Example: get_config services.rtsp.PORT  -> reads config/services/rtsp.conf key PORT
#          get_config system.TIMEZONE     -> reads config/system.conf       key TIMEZONE
#
# The argument is split on the LAST dot: everything after is the KEY, everything
# before is the file path (remaining dots become "/"). Keys are UPPERCASE and
# never contain dots, so the split is unambiguous.
#
# PERFORMANCE: on this CPU every fork costs ~50-70ms, so both functions use
# only shell builtins. But `X=$(get_config a.B)` still pays one fork for the
# command substitution itself -- scripts reading MORE THAN ONE key (or any key
# on a request/boot/per-event path) should use load_config below instead.
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

    # First match wins; strip up to the first '=' so '=' in values (passwords)
    # survives. The `|| [ -n ... ]` also takes a last line missing its newline.
    while IFS= read -r _gc_line || [ -n "$_gc_line" ]; do
        case "$_gc_line" in
            "$_gc_key"=*) printf '%s\n' "${_gc_line#*=}"; return 0 ;;
        esac
    done < "$_gc_file"

    # A missing key (vs an empty value, which is legitimate and silent) usually
    # means a caller was not migrated to the new key name.
    echo "get_config[ERROR]: key $_gc_key not found in $_gc_file" >&2
    return 1
}

# load_config <path> KEY [KEY...] - bulk variant of get_config.
# One pass over the file sets one shell variable PER KEY, named like the key:
#
#     load_config services.rtsp PORT STREAM   -> sets $PORT and $STREAM
#
# Same value semantics as get_config (first match wins, '=' in values kept).
# A key missing from the file leaves its variable untouched (a default assigned
# before the call survives), is reported on stderr, and the call returns 1.
load_config() {
    _lc_file="$CONFIG_DIR/${1//./\/}.conf"
    shift
    # Requested keys as " KEY1 KEY2 ... " (built without $* so a caller-modified
    # IFS cannot change the separator); found keys are removed as we go.
    _lc_left=" "
    for _lc_key in "$@"; do _lc_left="$_lc_left$_lc_key "; done

    if [ ! -f "$_lc_file" ]; then
        echo "load_config[ERROR]: file $_lc_file not found (keys$_lc_left)" >&2
        return 1
    fi

    while IFS= read -r _lc_line || [ -n "$_lc_line" ]; do
        case "$_lc_line" in ''|\#*) continue ;; *=*) ;; *) continue ;; esac
        _lc_key=${_lc_line%%=*}
        case "$_lc_left" in
            *" $_lc_key "*)
                # eval is safe: _lc_key was matched against the caller's literal
                # key list, and the value stays unexpanded inside \${...}.
                eval "$_lc_key=\${_lc_line#*=}"
                _lc_left=${_lc_left//" $_lc_key "/ }
                [ "$_lc_left" = " " ] && return 0
                ;;
        esac
    done < "$_lc_file"

    _lc_left=${_lc_left# }
    echo "load_config[ERROR]: key(s) ${_lc_left% } not found in $_lc_file" >&2
    return 1
}

# load_hw_ids - set HW_ID and SERIAL_NUMBER from the mmap.info blob.
#
# The field offsets differ per model. Callers must already have MODEL_SUFFIX
# (read from /home/app/.camver); pass it explicitly to keep this pure.
#
# Usage: load_hw_ids "$MODEL_SUFFIX"
#
# 2>/dev/null on dd is REQUIRED here, not laziness: dd reports its transfer
# stats ("4+0 records in") on stderr, and this runs inside $( ) where that
# would be harmless but noisy on every request. Because the redirect also
# swallows genuine errors (missing /tmp/mmap.info, a short read, an option this
# busybox build does not accept) the exit status is checked explicitly and a
# real diagnostic is emitted. Never suppress without that check.
load_hw_ids() {
    case "$1" in
        yi_dome_1080p|yi_cloud_dome_1080p) _hw_off=660; _sn_off=664 ;;
        *)                                 _hw_off=592; _sn_off=596 ;;
    esac

    HW_ID=$(dd bs=1 count=4 skip=$_hw_off if=/tmp/mmap.info 2>/dev/null) || {
        echo "load_hw_ids[ERROR]: dd failed reading HW_ID at $_hw_off from /tmp/mmap.info" >&2
        HW_ID=""; SERIAL_NUMBER=""; return 1
    }
    SERIAL_NUMBER=$(dd bs=1 count=16 skip=$_sn_off if=/tmp/mmap.info 2>/dev/null) || {
        echo "load_hw_ids[ERROR]: dd failed reading SERIAL_NUMBER at $_sn_off from /tmp/mmap.info" >&2
        SERIAL_NUMBER=""; return 1
    }

    # A successful dd that returned nothing means the blob is present but
    # shorter than the offset - worth knowing, and not the same as an error.
    [ -n "$HW_ID" ] || echo "load_hw_ids[WARN]: empty HW_ID (mmap.info shorter than $_hw_off?)" >&2
    return 0
}
