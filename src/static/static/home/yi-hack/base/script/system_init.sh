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
# system_init.sh - run by S01udev, very early in boot.
#
# There is nothing to do here anymore. Two things it used to do are now baked into
# the image at BUILD TIME (scripts/pack_fw.sh), so the result ships in and is
# verifiable from the flashed image:
#   - first-boot file placement (patch_stock_init, bake_app_overlays)
#   - big-file compression: files used to ship as *.7z and were expanded here on the
#     first boot. That only bought a slower, flash-writing first boot - the jffs2
#     image compresses its own contents anyway - so the files now ship uncompressed
#     and no runtime extraction is needed.
#
# Kept as a (no-op) hook: S01udev calls it unconditionally, and it is the natural
# place for any future "must run before /home/base/init.sh" one-shot.

:
