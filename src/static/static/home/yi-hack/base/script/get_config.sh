#!/bin/sh

# 0.1.0 - yi-hack-v6
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

    if [ ! -f "$_gc_file" ]; then
        echo "get_config: file $_gc_file not found (key $1)" >&2
        return 1
    fi

    # ^KEY= anchored (no spurious substring match); cut -f2- preserves '=' in values (passwords).
    if ! grep -qE "^${_gc_key}=" "$_gc_file"; then
        echo "get_config: key $_gc_key not found in $_gc_file" >&2
        return 1
    fi

    grep -E "^${_gc_key}=" "$_gc_file" | cut -d= -f2- | head -n1
}
