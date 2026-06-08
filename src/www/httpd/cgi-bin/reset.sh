#!/bin/sh

# 0.1.0

cd /home/yi-hack/config

rm hostname

rm camera.conf
rm -f services/mqtt.conf services/mqtt_advertise.conf
rm proxychains.conf
rm system.conf

bzip2 -d defaults.tar.bz2
tar xvf defaults.tar > /dev/null 2>&1

printf "Content-type: application/json\r\n\r\n"
printf "{\n"
printf "}\n"
