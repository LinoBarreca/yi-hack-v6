#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# locked_conf.sh - build-time locked settings (config/locked.conf).
#
# locked.conf is deployed at BUILD time (per model, see pack_fw.sh) and lists the
# settings this camera model is not allowed to change, one per line, in the same
# dotted syntax as get_config plus the forced value:
#
#     services.rtsp.STREAM=low
#     camera.AI_HUMAN_DETECTION=no
#
# A locked key cannot be overridden by the managed share config (apply_config),
# the web UI (set_configs/camera_settings), the rescue UI (rescue_lib.setkey) or
# MQTT cmnd/ (mqtt-config, C guard). restore_locked_configs stamps the forced
# values back into the target .conf files; the set paths use is_locked to refuse
# the change up front.
#
# Source this file, then use:
#   is_locked <section.KEY>   -> rc 0 when the key is locked
#   restore_locked_configs    -> re-stamp every locked value into its .conf
#
# NB: runtime writers that bypass our set paths (the Yi app via the stock cloud
# daemons -> mqttv4 persisting camera.conf) are NOT blocked here; the boot-time
# restore re-stamps those keys at the next boot.

CONFIG_DIR="${CONFIG_DIR:-/home/yi-hack/config}"
LOCKED_CONF="${LOCKED_CONF:-$CONFIG_DIR/locked.conf}"

# is_locked section.KEY -> 0 if present in locked.conf
is_locked() {
    [ -f "$LOCKED_CONF" ] || return 1
    grep -q "^$1=" "$LOCKED_CONF"
}

# Write every locked key back to its target file with the forced value.
# Flash-wear: a key already at the forced value is not rewritten.
restore_locked_configs() {
    [ -f "$LOCKED_CONF" ] || return 0
    while IFS= read -r _line; do
        case "$_line" in ''|\#*) continue ;; esac
        _path=${_line%%=*}
        _val=${_line#*=}
        _key=${_path##*.}
        _sec=${_path%.*}
        [ "$_sec" != "$_path" ] || { echo "locked_conf[ERROR]: malformed line '$_line' (need section.KEY=value)" >&2; continue; }
        _file="$CONFIG_DIR/${_sec//./\/}.conf"
        [ -f "$_file" ] || { echo "locked_conf[ERROR]: $_file not found (locked key $_path)" >&2; continue; }
        if grep -q "^${_key}=" "$_file"; then
            _cur=$(grep "^${_key}=" "$_file" | cut -d= -f2- | head -n1)
            if [ "$_cur" != "$_val" ]; then
                _ev=$(printf '%s' "$_val" | sed 's/[|&\\]/\\&/g')
                sed -i "s|^${_key}=.*|${_key}=${_ev}|" "$_file"
                echo "locked_conf: restored $_path=$_val"
            fi
        else
            printf '%s=%s\n' "$_key" "$_val" >> "$_file"
            echo "locked_conf: restored $_path=$_val (key was missing)"
        fi
    done < "$LOCKED_CONF"
    return 0
}
