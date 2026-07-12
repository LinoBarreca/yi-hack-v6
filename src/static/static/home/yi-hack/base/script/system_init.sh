#!/bin/sh

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
