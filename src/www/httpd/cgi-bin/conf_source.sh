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
# conf_source.sh - report which config files are MANAGED CENTRALLY, i.e. present
# in the share's/SD's config dir and therefore copied over flash at every boot by
# apply_config.sh. Source priority and exclusions mirror apply_config.sh.
#
#   (no args)     -> {"source":"<dir>","kind":"cifs"|"sd"|"","managed":[...]}
#                    kind drives the UI: cifs = fields read-only (central admin),
#                    sd = editable but the UI warns that a reboot with the SD
#                    inserted reverts the values to the provisioned ones.
#   ?file=<rel>   -> {"file":"<rel>","values":{"KEY":"value",...}} - the
#                    provisioning copy of one managed file (for the save warning).

. /home/yi-hack/base/script/get_config.sh

printf "Content-type: application/json\r\n\r\n"

read MODEL < /home/app/.camver
EXCLUDE="camera.conf ptz_presets.conf identity.conf hostname locked.conf"

config_on() {   # config_on <root> -> sets CONF_ON to the config dir, "" if none
    CONF_ON=""
    for _c in "$1/$MODEL/yi-hack/config" "$1/yi-hack/$MODEL/config" "$1/yi-hack/config"; do
        [ -d "$_c" ] && { CONF_ON="$_c"; return 0; }
    done
    return 1
}

# Boot reality: apply_config runs TWICE - before the CIFS mount (SD source) and
# after it (CIFS source). So the two trees apply in UNION, with the CIFS copy
# winning per-file. Report BOTH, per file, or the UI shows the wrong ownership
# (a system.conf provisioned only on the SD would look unmanaged).
# One builtin pass over /proc/mounts (never stat the mounts themselves - SMB1).
CIFS_RO_MOUNTED=no; SD_MOUNTED=no
while read -r _dev _mnt _; do
    case "$_mnt" in
        /tmp/cifs-ro) CIFS_RO_MOUNTED=yes ;;
        /tmp/sd)      SD_MOUNTED=yes ;;
    esac
done < /proc/mounts

load_config cifs ENABLED
SRC_CIFS=""; SRC_SD=""
if [ "$ENABLED" = "yes" ] && [ "$CIFS_RO_MOUNTED" = "yes" ]; then
    config_on /tmp/cifs-ro && SRC_CIFS=$CONF_ON
fi
if [ "$SD_MOUNTED" = "yes" ]; then
    config_on /tmp/sd && SRC_SD=$CONF_ON
fi

# ---- ?file=<rel>: dump the provisioning copy of one file ----
REL=""
OIFS=$IFS; IFS='&'
for _kv in $QUERY_STRING; do
    case "$_kv" in file=*) REL="${_kv#*=}"; break ;; esac
done
IFS=$OIFS

if [ -n "$REL" ]; then
    # path hygiene: relative, no dot-dot, conservative charset
    case "$REL" in *..*|/*|*[!A-Za-z0-9_./-]*) printf '{"error":"bad file"}'; exit 0 ;; esac
    # per-file precedence mirrors the boot order: the CIFS copy wins
    SRC=""
    [ -n "$SRC_CIFS" ] && [ -f "$SRC_CIFS/$REL" ] && SRC="$SRC_CIFS"
    [ -z "$SRC" ] && [ -n "$SRC_SD" ] && [ -f "$SRC_SD/$REL" ] && SRC="$SRC_SD"
    if [ -z "$SRC" ]; then
        printf '{"file":"%s","values":{}}' "$REL"; exit 0
    fi
    printf '{"file":"%s","values":{' "$REL"
    FIRST=1
    while IFS= read -r _line; do
        case "$_line" in ''|\#*) continue ;; esac
        case "$_line" in *=*) ;; *) continue ;; esac
        _k=${_line%%=*}
        case "$_k" in *[!A-Za-z0-9_]*|"") continue ;; esac
        # escape backslash and double quote for JSON (expansions, not sed:
        # the old per-line printf|sed forked twice per config line)
        _v=${_line#*=}
        _v=${_v//\\/\\\\}
        _v=${_v//\"/\\\"}
        [ "$FIRST" = 1 ] || printf ','
        printf '"%s":"%s"' "$_k" "$_v"
        FIRST=0
    done < "$SRC/$REL"
    printf '}}'
    exit 0
fi

# ---- default: per-source managed file lists ----
list_files() {   # list_files <dir> -> comma-separated JSON strings (only *.conf are provisioned)
    [ -n "$1" ] || return 0
    _first=1
    [ -d "$1" ] || { echo "conf_source[ERROR]: source dir $1 not found" >&2; return 0; }
    ( cd "$1" && find . -name '*.conf' -type f ) | while IFS= read -r f; do
        rel=${f#./}
        base=${rel##*/}
        case " $EXCLUDE " in *" $base "*) continue ;; esac
        [ "$_first" = 1 ] || printf ','
        printf '"%s"' "$rel"
        _first=0
    done
}
printf '{\n"cifs_source":"%s",\n"sd_source":"%s",\n' "$SRC_CIFS" "$SRC_SD"
printf '"cifs":[%s],\n' "$(list_files "$SRC_CIFS")"
printf '"sd":[%s]\n}'   "$(list_files "$SRC_SD")"
