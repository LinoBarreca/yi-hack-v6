#!/bin/bash

#
#  This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
#  Copyright (c) 2018-2019 Davide Maggioni - v4 specific
#  Copyright (c) 2021-2024 alienatedsec - v5 specific
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

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

source "$BASE_DIR/scripts/common.sh"

if [ -z "${FAKEROOTKEY:-}" ]; then
    exec fakeroot -- "$0" "$@"
fi

STOCK_DIR="$BASE_DIR/stock_firmware"
BUILD_DIR="$BASE_DIR/build"
VERSION=$(cat "$BASE_DIR/VERSION")
JFFS2_ERASE_BLOCK=64   # 64 KiB — matches Hi3518Ev200 NOR flash
JFFS2_PAGE_SIZE=4096   # 4 KiB — NOR flash standard (host may default to 16K on ARM64)

log() { printf "[pack] %s\n" "$*"; }
die() { log "ERROR: $*"; exit 1; }

###############################################################################
# Validate pre-conditions
###############################################################################

if [ $# -lt 1 ]; then
    echo "Usage: pack_fw.sh <model> [model2 ...]"
    echo ""
    echo "  <model> is a subdirectory of stock_firmware/ (e.g. y20)"
    echo "  Use 'all' to pack every model found in stock_firmware/."
    echo ""
    echo "Available models:"
    for d in "$STOCK_DIR"/*/; do
        [ -d "$d" ] && echo "  $(basename "$d")"
    done
    exit 1
fi

[ -d "$BUILD_DIR/rootfs" ] || die "build/rootfs/ not found — run ./build_all.sh compile first"
[ -d "$BUILD_DIR/home" ]   || die "build/home/ not found — run ./build_all.sh compile first"
[ -d "$BUILD_DIR/extra" ]  || die "build/extra/ not found — run ./build_all.sh compile first"

###############################################################################
# Expand 'all' into the list of models with extracted firmware
###############################################################################

MODELS=()
if [ "$1" = "all" ]; then
    for d in "$STOCK_DIR"/*/; do
        model=$(basename "$d")
        [ "$model" = "common" ] && continue
        [ "$model" = "jeffersonenv" ] && continue
        [ -d "$d/rootfs_extracted" ] && [ -d "$d/home_extracted" ] && MODELS+=("$model")
    done
    [ ${#MODELS[@]} -eq 0 ] && die "no models found with extracted firmware in stock_firmware/"
else
    MODELS=("$@")
fi

###############################################################################
# Helpers
###############################################################################

# Compress real files (not symlinks) in $dir into per-file .7z, removing the original.
# cd into the dir so the archive stores the bare basename -> system_init.sh extracts it
# back with `7za x <dir>/*.7z -o<dir>` to the same place.
compress_in_dir() {
    local dir=$1; shift
    [ -d "$dir" ] || return 0
    local f
    for f in "$@"; do
        if [ -f "$dir/$f" ] && [ ! -L "$dir/$f" ]; then
            ( cd "$dir" && 7za a "$f.7z" "$f" >/dev/null 2>&1 && rm -f "$f" ) \
                || die "7za failed on $dir/$f"
        fi
    done
}

# Stock OTA updates ship as a sibling folder of home_extracted/ named after the release
# (e.g. 2.1.0.0E_201809191630/) carrying a partial home/ tree with per-subdir version files
# (.basever/.appver/.libver/.hisikover) and a top-level homever. The stock updater
# (home/app/script/update.sh) version-gates each managed subdir and, when the update differs,
# wipes the subdir and drops the update's copy in. We fold that into the image at build time.
#
# Version strings end in a monotonic timestamp (..._YYYYMMDDHHMM); compare on that to decide
# "newer", falling back to plain inequality if absent.
ver_stamp() { printf '%s\n' "$1" | sed -n 's/.*_\([0-9]\{8,\}\).*/\1/p'; }
ver_gt() {                                   # ver_gt NEW CUR -> true if NEW strictly newer
    local n c; n=$(ver_stamp "$1"); c=$(ver_stamp "$2")
    if [ -n "$n" ] && [ -n "$c" ]; then [ "$n" -gt "$c" ] 2>/dev/null; return; fi
    [ "$1" != "$2" ]                         # no parseable stamp -> treat any difference as newer
}

# Apply every stock update folder found under $stock_root to $home_dir, oldest->newest,
# mirroring app/script/update.sh: per managed subdir, replace wholesale only when the update
# is newer; then refresh the top-level homever marker.
apply_stock_updates() {
    local home_dir=$1 stock_root=$2
    local updlist upd
    # NB: the loop's last iteration may be a dir without home/homever, so the pipeline exits
    # non-zero under pipefail -> `|| true` stops `set -e` aborting on a normal/empty result.
    updlist=$(for d in "$stock_root"/*/; do
                  [ -f "${d}home/homever" ] && basename "$d"
              done | sort -t_ -k2 -n) || true
    if [ -z "$updlist" ]; then
        log "$MODEL: no stock update folder found (no */home/homever) — using base home as-is"
        return 0
    fi
    for upd in $updlist; do
        local uhome="$stock_root/$upd/home"
        log "$MODEL: stock update '$upd' (homever $(cat "$uhome/homever" 2>/dev/null)) — current home homever $(cat "$home_dir/homever" 2>/dev/null || echo '<none>')"
        local spec sub vf newv curv
        for spec in "base:.basever" "app:.appver" "lib:.libver" "hisiko:.hisikover"; do
            sub=${spec%%:*}; vf=${spec##*:}
            [ -f "$uhome/$sub/$vf" ] || { log "$MODEL:   $sub: not in this update — skip"; continue; }
            newv=$(cat "$uhome/$sub/$vf") || true
            curv=$(cat "$home_dir/$sub/$vf" 2>/dev/null) || true
            if [ "$newv" = "${curv:-}" ]; then
                log "$MODEL:   $sub: already at $newv — skip"
            elif ver_gt "$newv" "${curv:-}"; then
                log "$MODEL:   $sub: REPLACE  ${curv:-<none>} -> $newv  ($(find "$uhome/$sub" -type f | wc -l) files)"
                rm -rf "$home_dir/$sub"
                mkdir -p "$home_dir/$sub"
                cp -a "$uhome/$sub/." "$home_dir/$sub/" || die "$MODEL: failed copying update $sub"
            else
                log "$MODEL:   $sub: update $newv NOT newer than $curv — keep current"
            fi
        done
        log "$MODEL:   homever -> $(cat "$uhome/homever")"
        cp -a "$uhome/homever" "$home_dir/homever"
    done
}

# Exact whole-line edits with a count assertion (safer than sed: a missing/dup target line
# ABORTS the build instead of being a silent no-op). Trailing whitespace is ignored.
# remove_line <file> <line> : delete the line; require it present EXACTLY once.
remove_line() {
    awk -v t="$2" '{ l=$0; sub(/[ \t]+$/,"",l) } l==t { c++; next } { print } END { if (c!=1) exit 3 }' \
        "$1" > "$1.tmp" || die "patch_stock_init: '$2' not found exactly once in $1"
    cat "$1.tmp" > "$1" && rm -f "$1.tmp"   # cat>dest keeps dest's mode (mv would drop +x)
}
# replace_line <file> <old> <new> : in-place, position-preserving; require <old> exactly once.
replace_line() {
    awk -v o="$2" -v n="$3" '{ l=$0; sub(/[ \t]+$/,"",l) } l==o { print n; c++; next } { print } END { if (c!=1) exit 3 }' \
        "$1" > "$1.tmp" || die "patch_stock_init: '$2' not found exactly once in $1"
    cat "$1.tmp" > "$1" && rm -f "$1.tmp"   # cat>dest keeps dest's mode (mv would drop +x)
}

# Patch the stock Xiaomi init scripts at BUILD TIME (verifiable here, in the image, instead
# of being re-applied on every camera at boot). The input is always pristine stock (fresh
# overlay), and the v6 OTA channel is the SD/U-Boot flash (stock Xiaomi OTA is closed), so
# the file is never reset under us - no runtime idempotency needed.
#  - app/init.sh : the cloud daemons are relaunched by yi-hack after build_view, so REMOVE
#                  the early stock launches (+ the now-orphan 'sleep 2'); bump swappiness 0->60.
#  - base/init.sh: REMOVE the hanging rtc time read.
patch_stock_init() {
    local app="$1/app/init.sh" base="$1/base/init.sh"
    log "$MODEL: patching stock init scripts (remove cloud daemons, swappiness, rtc)..."
    remove_line  "$app"  './log_server &'
    remove_line  "$app"  './dispatch &'
    remove_line  "$app"  './rmm &'
    remove_line  "$app"  './mp4record &'
    remove_line  "$app"  './cloud &'
    remove_line  "$app"  './p2p_tnp &'
    remove_line  "$app"  './oss &'
    remove_line  "$app"  './watch_process &'
    remove_line  "$app"  'sleep 2'
    replace_line "$app"  'echo 0 > /proc/sys/vm/swappiness'  'echo 60 > /proc/sys/vm/swappiness'
    remove_line  "$base" 'rtctime=$(/home/base/tools/rtctool -g time)'
    remove_line  "$base" 'date -s $rtctime'

    # DEBUG_LOG=early boot-log: right AFTER base/init.sh mounts the SD at /tmp/sd, and BEFORE it
    # runs app/init.sh (so the WiFi-driver detection IS captured), remount /tmp/sd -o sync and
    # redirect the boot-log there. This catches a pre-S20 hang WITHOUT a separate mountpoint, so
    # the FULL boot is preserved (no/yes boots leave the SD async/RAM exactly as before). Patched
    # into the stock script that owns the SD mount. remount,sync is unreliable on FAT -> umount +
    # 'mount -o sync'. The $(...) and tests are escaped to run on the CAMERA, not at pack time.
    replace_line "$base" 'mount /dev/mmcblk0p1 /tmp/sd' \
"mount /dev/mmcblk0p1 /tmp/sd
if [ \"\$(sed -n 's/^DEBUG_LOG=//p' /home/yi-hack/config/system.conf 2>/dev/null)\" = early ]; then
	umount /tmp/sd 2>/dev/null
	mount -o sync /dev/mmcblk0p1 /tmp/sd
	cp /dev/yi-boot.log /tmp/sd/yi-boot.log
	exec >> /tmp/sd/yi-boot.log 2>&1
	echo '===== [bootlog] DEBUG_LOG=early: live on SD /tmp/sd (-o sync) from base/init.sh ====='
fi"
}

# Bake the cloudAPI + udhcpc "first-boot file placement" into the home image at BUILD time.
# It used to run at runtime in system_init.sh (gated on cloudAPI_real not existing). Same
# rationale as patch_stock_init: the result is shipped in and verifiable from the flashed image,
# and the camera does no first-boot dance. Neuters the stock cloud (our cloudAPI wrapper calls
# cloudAPI_fake when DISABLE_CLOUD=yes, else cloudAPI_real) and installs our udhcpc/dhcp scripts.
# cloudAPI* / default.script are NOT *.sh, so the later blanket chmod skips them -> chmod here.
bake_app_overlays() {
    local h="$1" s="$1/yi-hack/base/script"
    log "$MODEL: baking cloudAPI + udhcpc overlays into /home/app (was runtime first-boot)..."
    [ -f "$s/cloudAPI" ] && [ -f "$s/cloudAPI_fake" ] || die "bake_app_overlays: cloudAPI source missing in $s"
    # stock cloudAPI -> cloudAPI_real (idempotent), then our wrapper + fake
    [ -f "$h/app/cloudAPI" ] && [ ! -f "$h/app/cloudAPI_real" ] && mv "$h/app/cloudAPI" "$h/app/cloudAPI_real"
    cp "$s/cloudAPI"      "$h/app/cloudAPI"
    cp "$s/cloudAPI_fake" "$h/app/cloudAPI_fake"
    chmod 0755 "$h/app/cloudAPI" "$h/app/cloudAPI_fake"
    [ -f "$h/app/cloudAPI_real" ] && chmod 0755 "$h/app/cloudAPI_real"
    # our udhcpc + dhcp scripts into /home/app/script
    cp "$s/default.script" "$h/app/script/default.script"; chmod 0755 "$h/app/script/default.script"
    if [ -f "$h/app/script/wifidhcp.sh" ]; then
        cp "$s/wifidhcp.sh" "$h/app/script/wifidhcp.sh"; chmod 0755 "$h/app/script/wifidhcp.sh"
    fi
}

# Build a jffs2 from $srcdir, then wrap it as the uImage U-Boot's do_auto_sd_update
# expects: file named <type>_<MODEL> (no extension), type=filesystem, comp=none.
make_partition_image() {
    local type=$1 srcdir=$2
    local jffs2="$IMG_DIR/${type}_${MODEL}.jffs2"
    local uimg="$IMG_DIR/${type}_${MODEL}"
    log "$MODEL: mkfs.jffs2 -> ${type}..."
    mkfs.jffs2 -l -e "$JFFS2_ERASE_BLOCK" --pagesize="$JFFS2_PAGE_SIZE" -r "$srcdir" -o "$jffs2" \
        || die "mkfs.jffs2 $type failed"
    log "$MODEL: uImage ($UIMAGE_TOOL) -> ${type}_${MODEL}..."
    if [ "$UIMAGE_TOOL" = "mkimage" ]; then
        mkimage -A arm -T filesystem -C none -n "0001-hi3518-${type}" -d "$jffs2" "$uimg" >/dev/null \
            || die "mkimage $type failed"
    else
        python3 "$BASE_DIR/scripts/mkuimage.py" -A arm -T filesystem -C none \
            -n "0001-hi3518-${type}" -d "$jffs2" "$uimg" || die "mkuimage.py $type failed"
    fi
    rm -f "$jffs2"
    log "$MODEL: ${type}_${MODEL} = $(stat -c '%s' "$uimg") bytes (uImage, jffs2 inside)"
}

###############################################################################
# Pack one model
###############################################################################

pack_model() {
    local MODEL=$1
    local MODEL_STOCK="$STOCK_DIR/$MODEL"
    local IMG_DIR="$BUILD_DIR/images/$MODEL"

    log "======== $MODEL (version $VERSION) ========"

    [ -d "$MODEL_STOCK/rootfs_extracted" ] || die "$MODEL: stock_firmware/$MODEL/rootfs_extracted/ not found"
    [ -d "$MODEL_STOCK/home_extracted" ]   || die "$MODEL: stock_firmware/$MODEL/home_extracted/ not found"

    rm -rf "$IMG_DIR"
    mkdir -p "$IMG_DIR"

    # --- Step 1: copy stock firmware as base ---
    log "$MODEL: copying stock rootfs..."
    cp -a "$MODEL_STOCK/rootfs_extracted" "$IMG_DIR/rootfs"

    log "$MODEL: copying stock home..."
    cp -a "$MODEL_STOCK/home_extracted" "$IMG_DIR/home"

    # --- Step 2: fold in stock OTA update(s) so the base is current before our overlay ---
    log "$MODEL: applying stock firmware update(s)..."
    apply_stock_updates "$IMG_DIR/home" "$MODEL_STOCK"

    # --- Step 3: overlay v6 build artifacts ---
    log "$MODEL: overlaying build/rootfs/ (busybox, init.d, profile)..."
    # --remove-destination: an overlay file must REPLACE a stock symlink at the same path, not
    # be written THROUGH it. e.g. our regular-file usr/bin/lsusb shim over stock's
    # usr/bin/lsusb -> ../../bin/busybox would otherwise clobber the busybox binary.
    cp -a --remove-destination "$BUILD_DIR/rootfs/." "$IMG_DIR/rootfs/"

    log "$MODEL: overlaying build/home/ (yi-hack base: scripts, www-min, dropbear, wpa, busybox_tools)..."
    cp -a --remove-destination "$BUILD_DIR/home/." "$IMG_DIR/home/"

    # --- Step 3b: per-model static overlay (applied AFTER the generic trees so it wins).
    # src/static/model/<MODEL>/{home,rootfs}/... mirrors the image layout. Used for
    # build-time forced settings a model cannot afford at runtime, e.g.
    # src/static/model/y20/home/yi-hack/config/locked.conf (see locked_conf.sh). ---
    local sub
    for sub in home rootfs; do
        if [ -d "$BASE_DIR/src/static/model/$MODEL/$sub" ]; then
            log "$MODEL: overlaying per-model static (src/static/model/$MODEL/$sub)..."
            cp -a --remove-destination "$BASE_DIR/src/static/model/$MODEL/$sub/." "$IMG_DIR/$sub/"
        fi
    done

    # --- Step 4: patch stock init scripts (build time -> verifiable in the image) ---
    patch_stock_init "$IMG_DIR/home"
    bake_app_overlays "$IMG_DIR/home"

    # --- Step 5: remove orphan uClibc copy (stock rootfs already has these in /lib) ---
    log "$MODEL: removing yi-hack/lib/ (uClibc duplicate, stock has /lib/)..."
    rm -rf "$IMG_DIR/home/yi-hack/lib"

    # --- Step 6: one-time substitutions ---
    # Replace stock wpa binaries with our build (security upgrade, WEXT-only)
    if [ -d "$BUILD_DIR/home/yi-hack/base/tools" ]; then
        log "$MODEL: upgrading wpa binaries in base/tools..."
        cp -a "$BUILD_DIR/home/yi-hack/base/tools/." "$IMG_DIR/home/base/tools/" 2>/dev/null || true
    fi

    # --- Step 7: strip comments + blank lines from shell scripts AND .conf (save flash space) ---
    # DELIBERATE: config comments live only in the source tree; the flashed .conf are terse
    # key=value (user edits them in the source/web UI, not by reading on-camera comments).
    log "$MODEL: stripping comments from scripts and .conf..."
    find "$IMG_DIR/home/yi-hack" "$IMG_DIR/rootfs/etc" \( -name '*.sh' -o -name '*.conf' \) | while read -r f; do
        [ -f "$f" ] || continue
        sed -i '/^[[:space:]]*#[^!]/d; /^[[:space:]]*$/d' "$f"
    done

    # --- Step 8: restore the EXECUTE BIT on every deployed script. A rewrite (sed -i strip,
    # patch_stock_init's awk>tmp, the static-overlay copy) can drop +x, and a non-executable boot
    # script = execve EACCES = dead boot. This is EXACTLY how base/init.sh (patched by
    # patch_stock_init, then non-+x) killed the boot: S01udev could not exec it, so the SD was
    # never mounted and the WiFi driver never loaded. .sh that are only sourced get +x too
    # (harmless); .conf are intentionally left non-executable. ---
    log "$MODEL: ensuring +x on all deployed scripts..."
    find "$IMG_DIR/home" "$IMG_DIR/rootfs" -name '*.sh' -exec chmod 0755 {} +
    chmod 0755 "$IMG_DIR/rootfs/etc/init.d/"S[0-9]* 2>/dev/null || true

    # --- Step 9: inject version ---
    mkdir -p "$IMG_DIR/home/yi-hack"
    echo "$VERSION" > "$IMG_DIR/home/yi-hack/version"

    # Camera model marker
    echo "$MODEL" > "$IMG_DIR/home/app/.camver"

    # --- Step 10: shrink — replace non-US audio with symlinks ---
    log "$MODEL: replacing non-US audio files with symlinks..."
    local audio_ext="*.aac"
    case "$MODEL" in
        y18) audio_ext="*726" ;;
    esac

    if [ -d "$IMG_DIR/home/app/audio_file/us" ]; then
        for audio in "$IMG_DIR/home/app/audio_file/us/"$audio_ext; do
            [ -f "$audio" ] || continue
            local name=$(basename "$audio")
            for lang in jp kr simplecn trditionalcn; do
                local target="$IMG_DIR/home/app/audio_file/$lang/$name"
                rm -f "$target"
                ln -s "../us/$name" "$target"
            done
        done
    fi

    # --- Step 11: compress big files (system_init.sh extracts them on first boot) ---
    # The home partition is tight (~13 MB). Big binaries/libs ship compressed and are
    # expanded once into the live /home on first boot by system_init.sh, which globs *.7z
    # in /home/app, /home/base/tools, /home/lib (and /home/yi-hack/yi-hack.7z).
    log "$MODEL: compressing big files (7za, extracted on first boot)..."
    compress_in_dir "$IMG_DIR/home/lib"        libcrypto.so.1.1 libstdc++.so.6.0.19
    compress_in_dir "$IMG_DIR/home/base/tools" wpa_supplicant wpa_passphrase wpa_cli
    compress_in_dir "$IMG_DIR/home/app"        cloudAPI oss p2p_tnp rmm

    # --- Step 12: fix ownership ---
    log "$MODEL: fixing ownership (root:root)..."
    chown -R root:root "$IMG_DIR/rootfs" "$IMG_DIR/home"

    # --- Step 13: build jffs2 then wrap as uImage (U-Boot do_auto_sd_update format) ---
    # The bootloader's SD-flash routine reads files named rootfs_<model>/home_<model>
    # (NO .jffs2 extension) in uImage format. A raw jffs2 is ignored. See design §2.11-bis.
    make_partition_image rootfs "$IMG_DIR/rootfs"
    make_partition_image home   "$IMG_DIR/home"

    # --- Step 14: SD/CIFS payload zip ---
    log "$MODEL: creating SD/CIFS payload zip..."
    local payload_staging="$IMG_DIR/payload"
    mkdir -p "$payload_staging/yi-hack/extra"
    cp -a "$BUILD_DIR/extra/." "$payload_staging/yi-hack/extra/"
        echo "$VERSION" > "$payload_staging/yi-hack/version"

    # extra/ holds only regular files (busybox binary + service binaries) - the applet
    # symlinks live in the flash farm (base/bin), not here - so the payload is FAT-safe and
    # the zip has no symlinks to preserve.
    (cd "$payload_staging" && zip -qr "$IMG_DIR/yi-hack-v6-${MODEL}-${VERSION}.zip" yi-hack/)
    local zip_size=$(stat -c '%s' "$IMG_DIR/yi-hack-v6-${MODEL}-${VERSION}.zip")
    log "$MODEL: payload zip: $zip_size bytes"

    # Clean up staging trees (keep only final artifacts)
    #rm -rf "$IMG_DIR/rootfs" "$IMG_DIR/home" "$IMG_DIR/payload"

    log "$MODEL: done. Output in build/images/$MODEL/"
    ls -lh "$IMG_DIR/"
    echo ""
}

###############################################################################
# Main
###############################################################################

# uImage wrapper: prefer real mkimage, but only if it actually runs. Under qemu-user on a
# 16K-page aarch64 host mkimage can't load libcrypto.so.3 (design §6.8) -> fall back to the
# dependency-free scripts/mkuimage.py. `mkimage -V` triggers the same load, so it's a clean probe.
if command -v mkimage >/dev/null 2>&1 && mkimage -V >/dev/null 2>&1; then
    UIMAGE_TOOL="mkimage"
else
    UIMAGE_TOOL="mkuimage.py"
fi

echo ""
echo "------------------------------------------------------------------------"
echo " yi-hack-v6 — FIRMWARE PACKAGER"
echo "------------------------------------------------------------------------"
echo " version    : $VERSION"
echo " models     : ${MODELS[*]}"
echo " uimage tool: $UIMAGE_TOOL"
echo "------------------------------------------------------------------------"
echo ""

for model in "${MODELS[@]}"; do
    pack_model "$model"
done

log "All done."
