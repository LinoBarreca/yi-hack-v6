#!/bin/sh

# 6.0.1
#
# save.sh - download a settings backup (tar.bz2). Includes the per-service
# configs under services/ (older versions missed them) and a version marker
# so load.sh can refuse restoring a backup from an incompatible firmware.

printf "Content-type: application/octet-stream\r\n\r\n"

TMP_DIR="/tmp/yi-temp-save"
rm -rf $TMP_DIR
mkdir $TMP_DIR
cd $TMP_DIR

cp /home/yi-hack/config/*.conf .
if [ -d /home/yi-hack/config/services ]; then
    mkdir services
    cp /home/yi-hack/config/services/*.conf services/ 2>/dev/null
fi
if [ -f /home/yi-hack/config/hostname ]; then
    cp /home/yi-hack/config/hostname .
fi
# version marker (no leading dot: `tar cvf ... *` must pick it up)
cp /home/yi-hack/version ./backup_version 2>/dev/null

tar cvf config.tar * > /dev/null
bzip2 config.tar
cat $TMP_DIR/config.tar.bz2
cd /tmp
rm -rf $TMP_DIR
