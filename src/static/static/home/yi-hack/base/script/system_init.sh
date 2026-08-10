#!/bin/sh

#
#  This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
#  Copyright (c) 2021-2023 alienatedsec - v5 specific
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
# system_init.sh - run by S01udev, very early in boot, before /home/base/init.sh.
#
# Two things this used to do are now baked into the image at BUILD TIME
# (scripts/pack_fw.sh), so the result ships in and is verifiable from the flashed
# image:
#   - first-boot file placement (patch_stock_init, bake_app_overlays)
#   - big-file compression: files used to ship as *.7z and were expanded here on the
#     first boot. That only bought a slower, flash-writing first boot - the jffs2
#     image compresses its own contents anyway - so the files now ship uncompressed
#     and no runtime extraction is needed.
#
# What it does do is light the status LED, which has to happen as early as
# possible and could not happen any earlier than this.

# --- Status LED, phase 1 (pre-network) --------------------------------------
# This is the first point in the boot where the LED CAN be driven: S01udev has
# just mounted /home, so both the driver and ledctl are reachable. It is also
# where it MATTERS most - everything after this can take tens of seconds (WiFi
# association, CIFS mount), and until something lights up the camera is
# indistinguishable from a dead one.
#
# Nothing loads the LED driver at boot: the stock binaries insmod it lazily, the
# first time one of them wants a LED, so in native pipeline mode (where none of
# them ever runs) it would never be loaded at all. We load it ourselves.
#
# Which file: localko ships cpld_periph.ko and cpld_periph_v3.ko, and the rule
# stock uses to pick between them is not known - its helper carries one function
# per variant and the caller is in a binary we have not traced. The y20 runs the
# non-v3 one, which is the board our command map was verified on, so that is the
# one we load. On the stock path system.sh unloads it again before the stock
# stack starts, so stock is still free to load whichever variant it wants; see
# the handoff there.
#
# Errors are logged rather than suppressed: a camera that never lights its LED
# is a support question, and this is the line that explains it.
if [ ! -c /dev/cpld_periph ]; then
    insmod /home/app/localko/cpld_periph.ko || \
        echo "system_init.sh: insmod cpld_periph.ko failed - no status LED this boot"
fi
# Absolute path: S01udev's PATH does not include base/bin.
/home/yi-hack/base/bin/ledctl pattern boot-early
