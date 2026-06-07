#!/bin/sh
# Helpers for the rescue CGI: read x-www-form-urlencoded POST, decode fields, write config keys.
CONFIG=/home/yi-hack/config

read_body() { read -r BODY; }

# urldecode: '+' -> space, %XX -> byte
urldecode() { _d="${1//+/ }"; printf '%b' "${_d//%/\\x}"; }

# get_field NAME -> decoded value of NAME from $BODY (no eval; only known keys are queried)
# NB: busybox on the camera has no 'head'; use awk for "first match".
get_field() { _v=$(printf '%s' "$BODY" | tr '&' '\n' | grep "^$1=" | awk 'NR==1{print;exit}'); urldecode "${_v#*=}"; }

# setkey FILE KEY VALUE -> set KEY=VALUE in $CONFIG/FILE (update in place or append)
setkey() {
    _f="$CONFIG/$1"; touch "$_f"
    if grep -qE "^$2=" "$_f"; then
        _ev=$(printf '%s' "$3" | sed 's/[|&\\]/\\&/g')
        sed -i "s|^$2=.*|$2=$_ev|" "$_f"
    else
        printf '%s=%s\n' "$2" "$3" >> "$_f"
    fi
}
