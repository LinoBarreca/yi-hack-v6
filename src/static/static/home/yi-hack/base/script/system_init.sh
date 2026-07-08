#!/bin/sh

# 6.0.1

if [ -d "/usr/yi-hack" ]; then
    YI_HACK_V6_PREFIX="/usr"
    YI_PREFIX="/home"
elif [ -d "/home/yi-hack" ]; then
    YI_HACK_V6_PREFIX="/home"
    YI_PREFIX="/home/app"
    YI_BASE="/home/base/tools"
    YI_LIB="/home/lib"
fi

ARCHIVE_FILE="$YI_HACK_V6_PREFIX/yi-hack/yi-hack.7z"
DESTDIR="$YI_HACK_V6_PREFIX/yi-hack"

files=`find $YI_PREFIX -maxdepth 1 -name "*.7z" | awk 'END { print NR }'`
if [ $files -gt 0 ]; then
	/home/base/tools/7za x "$YI_PREFIX/*.7z" -y -o$YI_PREFIX
	rm $YI_PREFIX/*.7z
fi

files=`find $YI_BASE -maxdepth 1 -name "*.7z" | awk 'END { print NR }'`
if [ $files -gt 0 ]; then
	/home/base/tools/7za x "$YI_BASE/*.7z" -y -o$YI_BASE
	rm $YI_BASE/*.7z
fi

files=`find $YI_LIB -maxdepth 1 -name "*.7z" | awk 'END { print NR }'`
if [ $files -gt 0 ]; then
	/home/base/tools/7za x "$YI_LIB/*.7z" -y -o$YI_LIB
	rm $YI_LIB/*.7z
fi

if [ -f $ARCHIVE_FILE ]; then
	/home/base/tools/7za x $ARCHIVE_FILE -y -o$DESTDIR
	rm $ARCHIVE_FILE
fi

# config/crontabs and config/dropbear ship (empty) in the home image at build time - no runtime mkdir.

# NOTE: the "first-boot file placement" is no longer done here at runtime - it is baked at BUILD
# TIME in scripts/pack_fw.sh, so the result is shipped in and verifiable from the flashed image:
#   - patch_stock_init:  comment out stock cloud daemons, swappiness, rtc
#   - bake_app_overlays: stock cloudAPI -> cloudAPI_real; install our cloudAPI/cloudAPI_fake +
#                        udhcpc/dhcp scripts into /home/app.
# This script now only extracts the *.7z shipped compressed (will be removed next).
