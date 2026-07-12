#!/bin/sh

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

MODEL=$(cat /home/app/.camver 2>/dev/null)
EXCLUDE="camera.conf ptz_presets.conf identity.conf hostname locked.conf"

config_on() {
    for _c in "$1/$MODEL/yi-hack/config" "$1/yi-hack/$MODEL/config" "$1/yi-hack/config"; do
        [ -d "$_c" ] && { echo "$_c"; return 0; }
    done
    return 1
}

# Boot reality: apply_config runs TWICE - before the CIFS mount (SD source) and
# after it (CIFS source). So the two trees apply in UNION, with the CIFS copy
# winning per-file. Report BOTH, per file, or the UI shows the wrong ownership
# (a system.conf provisioned only on the SD would look unmanaged).
SRC_CIFS=""; SRC_SD=""
if [ "$(get_config cifs.ENABLED)" = "yes" ] && grep -q " /tmp/cifs-ro " /proc/mounts; then
    SRC_CIFS=$(config_on /tmp/cifs-ro)
fi
if grep -q " /tmp/sd " /proc/mounts; then
    SRC_SD=$(config_on /tmp/sd)
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
        # escape backslash and double quote for JSON
        _v=$(printf '%s' "${_line#*=}" | sed 's/\\/\\\\/g; s/"/\\"/g')
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
    ( cd "$1" 2>/dev/null && find . -name '*.conf' -type f ) | while IFS= read -r f; do
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
