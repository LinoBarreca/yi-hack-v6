#!/bin/sh

# 6.0.1

if [ -d "/usr/yi-hack" ]; then
    YI_HACK_V5_PREFIX="/usr"
    YI_PREFIX="/home"
    UDHCPC_SCRIPT_DEST="/home/default.script"
elif [ -d "/home/yi-hack" ]; then
    YI_HACK_V5_PREFIX="/home"
    YI_PREFIX="/home/app"
    YI_BASE="/home/base/tools"
    YI_LIB="/home/lib"
    UDHCPC_SCRIPT_DEST="/home/app/script/default.script"
fi

ARCHIVE_FILE="$YI_HACK_V5_PREFIX/yi-hack/yi-hack.7z"
DESTDIR="$YI_HACK_V5_PREFIX/yi-hack"

DHCP_SCRIPT_DEST="/home/app/script/wifidhcp.sh"
UDHCP_SCRIPT="$YI_HACK_V5_PREFIX/yi-hack/base/script/default.script"
DHCP_SCRIPT="$YI_HACK_V5_PREFIX/yi-hack/base/script/wifidhcp.sh"

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

if [ ! -f $YI_PREFIX/cloudAPI_real ]; then
	mv $YI_PREFIX/cloudAPI $YI_PREFIX/cloudAPI_real
	cp $YI_HACK_V5_PREFIX/yi-hack/base/script/cloudAPI $YI_PREFIX/
	cp $YI_HACK_V5_PREFIX/yi-hack/base/script/cloudAPI_fake $YI_PREFIX/
        rm $UDHCPC_SCRIPT_DEST
        cp $UDHCP_SCRIPT $UDHCPC_SCRIPT_DEST
	if [ -f $DHCP_SCRIPT_DEST ]; then
		rm $DHCP_SCRIPT_DEST
		cp $DHCP_SCRIPT $DHCP_SCRIPT_DEST
	fi
fi

# config/crontabs and config/dropbear ship (empty) in the home image at build time - no runtime mkdir.

# NOTE: patching the stock init scripts (comment cloud daemons, swappiness, rtc) is no longer
# done here at runtime - it is done at BUILD TIME in scripts/pack_fw.sh (patch_stock_init),
# so the result is baked into and verifiable in the flashed image.
