#!/bin/bash

#
#  This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
#  Copyright (c) 2018-2019 Davide Maggioni.
#  Copyright (c) 2021 alienatedsec.
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

get_script_dir()
{
    echo "$(cd `dirname $0` && pwd)"
}

compile_module()
{
    (
    local MOD_DIR=$1
    local MOD_NAME=$(basename "$MOD_DIR")
    
    local MOD_INIT="init.$MOD_NAME"
    local MOD_COMPILE="compile.$MOD_NAME"
    local MOD_INSTALL="install.$MOD_NAME"
    
    printf "MOD_DIR:        %s\n" "$MOD_DIR"
    printf "MOD_NAME:       %s\n" "$MOD_NAME"
    printf "MOD_INIT:       %s\n" "$MOD_INIT"
    printf "MOD_COMPILE:    %s\n" "$MOD_COMPILE"
    printf "MOD_INSTALL:    %s\n" "$MOD_INSTALL"
    
    echo "Compile $MOD_NAME"
    cd "$MOD_DIR"
    
    if [ ! -f $MOD_INIT ]; then
        echo "$MOD_INIT not found.. exiting."
        exit 1
    fi
    if [ ! -f $MOD_COMPILE ]; then
        echo "$MOD_COMPILE not found.. exiting."
        exit 1
    fi
    if [ ! -f $MOD_INSTALL ]; then
        echo "$MOD_INSTALL not found.. exiting."
        exit 1
    fi
    
    echo ""
    
    printf "Initializing $MOD_NAME...\n\n"
    ./$MOD_INIT || exit 1
    
    printf "Compiling $MOD_NAME...\n\n"
    ./$MOD_COMPILE || exit 1
    
    printf "Installing '$MOD_INSTALL' in the firmware...\n\n"
    ./$MOD_INSTALL || exit 1
    
    printf "\n\nDone!\n\n"
    )
}

###############################################################################

source "$(get_script_dir)/common.sh"

echo ""
echo "------------------------------------------------------------------------"
echo " yi-hack-v6 - SRC COMPILER"
echo "------------------------------------------------------------------------"
echo ""

# this is needed because with sudo the PATH apparently doesn't contain it. Idk why
# Hisilicon Linux, Cross-Toolchain PATH
export PATH="/opt/arm-hisiv300-linux/bin:$PATH"

SRC_DIR=$(get_script_dir)/../src
SELECTED_MODULE=$1

# Full build (no module arg) wipes build/ for a clean tree. A targeted build
# (compile.sh <module>) KEEPS build/ and only rebuilds/reinstalls that module's
# artifacts, so a single module can be iterated - and its output deployed - without
# recompiling everything.
if [ -z "$SELECTED_MODULE" ]; then
    rm -rf "$(get_script_dir)/../build/"
else
    echo "SELECTED_MODULE: $SELECTED_MODULE (incremental: keeping existing build/)"
fi

mkdir -p "$(get_script_dir)/../build/home"
mkdir -p "$(get_script_dir)/../build/rootfs"
# Raw SD/CIFS payload contents (full www, optional service binaries)
# — NOT homefs/flash, which only ships base binaries + www-min (rescue).
# The packager wraps this into the share structure (yi-hack/extra/) and adds version.
mkdir -p "$(get_script_dir)/../build/extra"

# Modules deliberately NOT built (space-separated basenames).
#   uClibc++ : source unavailable (git.busybox.net TLS cert expired) and not linked by
#              any module (onvif builds with the toolchain's C++ lib). Re-enable once the
#              submodule can be fetched, if a payload binary ever needs libuClibc++.
#   libfuse  : no module links it (-lfuse) and nothing FUSE-based is deployed; it would
#              ship libfuse3.so as dead weight. The kernel HAS FUSE builtin, so re-enable
#              if/when a FUSE feature is actually added.
#   curl     : the curl binary is unused (v6 scripts use busybox wget); its libssl.so.1.1
#              is redundant too (wget-https works via libcrypto from wpa + busybox TLS).
#              Skipping also drops a slow openssl-under-qemu build. Re-enable if a real
#              curl/libcurl consumer appears.
SKIP_MODULES="uClibc++ libfuse curl"

for SUB_DIR in $SRC_DIR/* ; do
    if [ -d ${SUB_DIR} ]; then # Will not run if no directories are available
        case " $SKIP_MODULES " in
            *" $(basename "$SUB_DIR") "*) echo "Skip $SUB_DIR (disabled in SKIP_MODULES)"; continue ;;
        esac
        if [ -n "$SELECTED_MODULE" ]; then
            if [[ $SUB_DIR == *"$SELECTED_MODULE"* ]]; then
                compile_module $(normalize_path "$SUB_DIR") || exit 1
            else
                echo "Skip $SUB_DIR"
            fi
        else
            compile_module $(normalize_path "$SUB_DIR") || exit 1
        fi
    fi
done

BIN_DIR=$(get_script_dir)/../bin
BUILD_DIR=$(get_script_dir)/../build

if [ -d "$BIN_DIR" ]; then
    cp -R $BIN_DIR/* $BUILD_DIR/
fi


