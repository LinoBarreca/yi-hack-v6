#!/bin/sh

# 0.1.0 - yi-hack-v6
#
# version_compat.sh - base <-> payload version handshake (sections 5.8, 9).
#
# The flash BASE (/home/yi-hack/version) and the network/SD PAYLOAD
# (<payload_root>/version, i.e. extra/version) are versioned independently. A
# payload built for a different base may ship config of a different schema or
# binaries of a different ABI -> applying it would push wrong settings/binaries.
# So before applying the managed config (apply_config.sh) or booting the payload
# (build_view.sh) we require the two to be COMPATIBLE.
#
# Rule: compatible iff base and payload share the same MAJOR.MINOR (the patch
# level may differ, e.g. base 0.1.0 <-> payload 0.1.7 is OK; 0.1.x <-> 0.2.x is not).
# A missing/empty version on either side -> NOT compatible (refuse; safer).
#
# Usage:  . version_compat.sh ; payload_compatible <payload_root>   # 0=ok, 1=no
#   <payload_root> = the yi-hack dir on the share/SD; the payload version is read
#   from <payload_root>/extra/version (mirrors flash /home/yi-hack/extra/version).
# Test override: BASE_VERSION_FILE
: "${BASE_VERSION_FILE:=/home/yi-hack/version}"

# echo the MAJOR.MINOR of a version string (e.g. "0.1.7" -> "0.1")
_ver_mm() { echo "$1" | cut -d. -f1,2; }

payload_compatible() {
    _vc_pr="$1"
    _vc_base=$(cat "$BASE_VERSION_FILE" 2>/dev/null)
    _vc_payload=$(cat "$_vc_pr/extra/version" 2>/dev/null)

    if [ -z "$_vc_base" ] || [ -z "$_vc_payload" ]; then
        echo "version_compat: missing version (base='$_vc_base' payload='$_vc_payload') -> incompatible"
        return 1
    fi
    if [ "$(_ver_mm "$_vc_base")" = "$(_ver_mm "$_vc_payload")" ]; then
        echo "version_compat: base $_vc_base / payload $_vc_payload -> compatible"
        return 0
    fi
    echo "version_compat: base $_vc_base / payload $_vc_payload -> MAJOR.MINOR mismatch -> incompatible"
    return 1
}
