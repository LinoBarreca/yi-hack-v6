#!/bin/sh

# 6.0.1

printf "Content-type: application/octet-stream\r\n\r\n"

TMP_DIR="/tmp/yi-temp-save"
mkdir $TMP_DIR
cd $TMP_DIR
cp /home/yi-hack/config/*.conf .
if [ -f /home/yi-hack/config/hostname ]; then
    cp /home/yi-hack/config/hostname .
fi
tar cvf config.tar * > /dev/null
bzip2 config.tar
cat $TMP_DIR/config.tar.bz2
cd /tmp
rm -rf $TMP_DIR
