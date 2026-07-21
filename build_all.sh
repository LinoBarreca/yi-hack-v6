#!/usr/bin/env bash

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

#
# yi-hack-v6 build orchestrator.
#
# Builds the cross-build Docker image (canonical HiSilicon arm-hisiv300 toolchain,
# GCC 4.8.3 / uClibc 0.9.33.2 — see docker/Dockerfile) and drives the build/packaging
# inside it. On a non-x86 host (e.g. the
# aarch64 RPi5) it registers qemu-user binfmt first, so everything stays containerized
# and the host filesystem is not polluted.
#
# Usage:
#   ./build_all.sh image     # register binfmt (if needed) + build the toolchain image
#   ./build_all.sh hello     # smoke-test: compile a uClibc ARMv5 binary in the image
#   ./build_all.sh shell     # interactive shell inside the build image
#   ./build_all.sh sysroot   # (not required — no module links a camera sysroot)
#   ./build_all.sh compile   # cross-compile the src/ modules into build/{rootfs,home,extra}
#   ./build_all.sh pack [m]  # overlay stock firmware + build → jffs2 images + SD/CIFS zip
#   ./build_all.sh all       # full pipeline, then unregister qemu binfmt (clean exit)
#   ./build_all.sh clean     # teardown: unregister qemu binfmt + remove the build image
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="yihack-v6-build"
PLATFORM="linux/amd64"   # the toolchain is i386; base image amd64 + i386 multiarch

log() { echo "[build_all] $*"; }

ensure_binfmt() {
    case "$(uname -m)" in
        x86_64|i386|i686) return 0 ;;   # native x86, no emulation needed
    esac
    if [ ! -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ] || [ ! -e /proc/sys/fs/binfmt_misc/qemu-i386 ]; then
        log "host $(uname -m): registering qemu-user binfmt (amd64,386) via tonistiigi/binfmt..."
        docker run --privileged --rm tonistiigi/binfmt --install amd64,386
    else
        log "qemu binfmt (x86_64 + i386) already registered."
    fi
}

cleanup_binfmt() {
    case "$(uname -m)" in
        x86_64|i386|i686) return 0 ;;   # nothing was registered on native x86
    esac
    if [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ] || [ -e /proc/sys/fs/binfmt_misc/qemu-i386 ]; then
        log "cleanup: unregistering qemu-user binfmt (amd64,386)..."
        docker run --privileged --rm tonistiigi/binfmt --uninstall qemu-x86_64,qemu-i386 || true
    fi
}

build_image() {
    ensure_binfmt
    log "building image $IMAGE (platform $PLATFORM)..."
    docker build --platform="$PLATFORM" -t "$IMAGE" "$ROOT/docker"
    log "done. Toolchain:"
    docker run --rm --platform="$PLATFORM" "$IMAGE" arm-hisiv300-linux-uclibcgnueabi-gcc --version | head -1
}

# Run as the host uid:gid so build artifacts are owned by the user (not root) and git
# trusts the mounted repo (no "dubious ownership"). HOME -> /tmp (writable for the uid).
run_in_image() { docker run --rm --platform="$PLATFORM" --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT:/work" "$IMAGE" "$@"; }

# Static boot-simulation gate: every packaged image must pass scripts/simulate_boot.py before we
# consider the pack good. It catches dead-boot defects the toolchain can't (e.g. a boot script
# that lost its execute bit = execve EACCES = brick). Runs on the HOST (python3/objdump live here,
# not in the build container). Any ERROR aborts the build.
boot_sim_gate() {
    command -v python3 >/dev/null 2>&1 || { log "boot-sim gate: python3 not found — SKIPPED"; return 0; }
    local m
    for m in "$ROOT"/build/images/*/; do
        [ -d "$m" ] || continue
        m=$(basename "$m")
        log "boot-sim gate: simulating boot of '$m' ..."
        if ! python3 "$ROOT/scripts/simulate_boot.py" "$m" >/dev/null; then
            log "!!!! BOOT SIMULATION FAILED for '$m' — see simulated_boot.log — PACK REJECTED !!!!"
            exit 1
        fi
    done
    log "boot-sim gate: all packaged images PASS"
}

hello() {
    log "smoke-test: cross-compiling docker/hello.c (uClibc ARMv5) in $IMAGE ..."
    mkdir -p "$ROOT/build"
    run_in_image sh -euc '
        arm-hisiv300-linux-uclibcgnueabi-gcc -march=armv5te -mcpu=arm926ej-s /work/docker/hello.c -o /work/build/hello.armv5
        file /work/build/hello.armv5
        arm-hisiv300-linux-uclibcgnueabi-readelf -A /work/build/hello.armv5 | grep -E "CPU_arch|FP" | head
    '
    log "built -> build/hello.armv5 (dynamic uClibc; matches the camera uClibc 0.9.33.2)."
}

usage() {
    cat <<'EOF'
yi-hack-v6 build orchestrator. Usage: ./build_all.sh <cmd>
  image     register qemu binfmt (if needed) + build the toolchain image
  hello     smoke-test: compile a uClibc ARMv5 binary in the image
  shell     interactive shell inside the build image
  sysroot   (not required — no module links a camera sysroot)
  compile   cross-compile src/ modules into build/{rootfs,home,extra}
  pack [m]  produce jffs2 images + SD/CIFS zip (all models, or pass model code)
  all       full pipeline, then unregister qemu binfmt on exit
  clean     teardown: unregister qemu binfmt + remove the build image
EOF
}

case "${1:-help}" in
    help|-h|--help) usage ;;
    image)   build_image ;;
    hello)   hello ;;
    shell)   ensure_binfmt; docker run --rm -it --platform="$PLATFORM" -v "$ROOT:/work" "$IMAGE" bash ;;
    sysroot) log "NOTE: not required — no src module links a camera sysroot; they build against"
             log "      the toolchain's bundled uClibc target/."
             log "      init_sysroot.sh (root + jffs2 mount) is kept only for niche needs."; exit 0 ;;
    compile) ensure_binfmt
             log "cross-compiling ${2:-ALL modules} in $IMAGE (canonical toolchain)..."
             run_in_image bash scripts/compile.sh "${2:-}"
             log "built into build/{rootfs,home,extra}/." ;;
    pack)    ensure_binfmt
             log "packing firmware images for ${2:-all} models (in container)..."
             run_in_image bash scripts/pack_fw.sh "${2:-all}"
             boot_sim_gate
             log "done — images in build/images/." ;;
    clean)   cleanup_binfmt; docker rmi "$IMAGE" 2>/dev/null || true; log "teardown done (image $IMAGE + qemu binfmt removed)." ;;
    all)     trap cleanup_binfmt EXIT
             build_image
             hello
             log "cross-compiling ALL modules..."
             run_in_image bash scripts/compile.sh ""
             log "packing firmware images for all models..."
             run_in_image bash scripts/pack_fw.sh all
             boot_sim_gate
             log "all done. Images in build/images/." ;;
    *)       echo "usage: $0 {image|hello|shell|sysroot|compile|pack|all|clean}" >&2; exit 2 ;;
esac
