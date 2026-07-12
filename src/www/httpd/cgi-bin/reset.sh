#!/bin/sh

# 6.0.1
#
# Factory reset of the managed configuration: delete the declarative/runtime
# config files (system, recording, camera, services/*) and let check_conf.sh
# re-seed them with defaults. Per-camera identity (identity.conf), network
# (wifi.conf, cifs.conf), hostname and PTZ presets are PRESERVED so the camera
# stays reachable and uniquely identified after the reset.

cd /home/yi-hack/config || exit 1

rm -f system.conf recording.conf camera.conf
rm -f services/snapshot.conf services/httpd.conf services/rtsp.conf \
      services/onvif.conf services/telnetd.conf services/sshd.conf \
      services/ftpd.conf services/ftp_upload.conf services/ntpd.conf \
      services/proxychains.conf services/mqtt.conf services/mqtt_advertise.conf

# Re-seed the removed files with defaults (check_conf.sh leaves preserved files
# untouched; it also runs again at boot from system.sh), then re-stamp the
# build-time locked values (generic defaults may differ from them).
/home/yi-hack/base/script/check_conf.sh
/home/yi-hack/base/script/restore_locked_configs.sh

printf "Content-type: application/json\r\n\r\n"
printf "{\n"
printf "}\n"
