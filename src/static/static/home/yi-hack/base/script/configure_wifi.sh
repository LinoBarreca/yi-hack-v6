#!/bin/sh

# 6.0.1

function print_help {
    echo "configure_wifi.sh"
    echo "will be used on next boot"
}

if [ -f "/tmp/sd/recover/mtdblock2_recover.bin" ]; then
    DATE=$(date '+%Y%m%d%H%M%S')
    # This path restores the wifi partition from SD and then reboots. dd's
    # output is NOT suppressed: it goes to the boot log, and a failure here
    # must be visible - we are about to overwrite /dev/mtdblock2 and rename
    # the recovery file away, so a silent failure costs the only copy of both
    # the pre-recovery backup and the recovery image.
    if ! dd if=/dev/mtdblock2 of=/tmp/sd/recover/mtdblock2_prerecover_$DATE.bin; then
        echo "configure_wifi: pre-recovery backup FAILED - refusing to overwrite mtdblock2"
        exit 1
    fi
    if ! dd if=/tmp/sd/recover/mtdblock2_recover.bin of=/dev/mtdblock2; then
        echo "configure_wifi: restore to mtdblock2 FAILED - keeping the recovery file for a retry"
        exit 1
    fi
    mv /tmp/sd/recover/mtdblock2_recover.bin /tmp/sd/recover/mtdblock2_recover_done.bin
    reboot
fi

CFG_FILE=/tmp/configure_wifi.cfg
if [ ! -f "$CFG_FILE" ]; then
    echo "configure_wifi.cfg not found"
    exit 1
fi

TMP=$(grep wifi_ssid= "$CFG_FILE")
SSID=$(echo "${TMP:10}")
TMP=$(grep wifi_psk= "$CFG_FILE")
KEY=$(echo "${TMP:9}")

if [ -z "$SSID" ]; then
    echo "error: ssid has not been set"
    print_help
    exit 1
fi
if [ ${#SSID} -gt 63 ]; then
    echo "error: ssid is too long"
    print_help
    exit 1
fi

if [ -z "$KEY" ]; then
    echo "error: key has not been set"
    print_help
    exit 1
fi
if [ ${#KEY} -gt 63 ]; then
    echo "error: key is too long"
    print_help
    exit 1
fi

# 2>/dev/null keeps dd's transfer stats out of the captured value; the rc is
# checked because it also hides a genuine read failure, which would make both
# fields look empty and the "already configured" test below silently wrong.
CURRENT_SSID=$(dd bs=1 skip=28 count=64 if=/dev/mtdblock2 2>/dev/null) || \
    { echo "error: cannot read current SSID from /dev/mtdblock2"; exit 1; }
CURRENT_KEY=$(dd bs=1 skip=92 count=64 if=/dev/mtdblock2 2>/dev/null) || \
    { echo "error: cannot read current key from /dev/mtdblock2"; exit 1; }

echo $SSID ${#SSID} - $CURRENT_SSID ${#CURRENT_SSID}
echo $KEY ${#KEY} - $CURRENT_KEY ${#CURRENT_KEY}

if [ "$SSID" == "$CURRENT_SSID" ] && [ "$KEY" == "$CURRENT_KEY" ]; then
    echo "ssid and key already configured"
    exit
fi

echo "creating partition backup..."
DATE=$(date '+%Y%m%d%H%M%S')
# Not suppressed, and checked: the writes below are destructive and this is
# the only copy of the pre-change partition.
if ! dd if=/dev/mtdblock2 of=/tmp/sd/mtdblock2_$DATE.bin; then
    echo "error: partition backup failed - refusing to modify /dev/mtdblock2"
    exit 1
fi

# clear the existing passwords (to ensure we are null terminated)
dd if=/dev/zero of=/dev/mtdblock2 bs=1 seek=28 count=64 conv=notrunc
dd if=/dev/zero of=/dev/mtdblock2 bs=1 seek=92 count=64 conv=notrunc
# write SSID
echo -n "$SSID" | dd of=/dev/mtdblock2 bs=1 seek=28 count=64 conv=notrunc
# write key
echo -n "$KEY" | dd of=/dev/mtdblock2 bs=1 seek=92 count=64 conv=notrunc
#write "connected" bit
printf "\00\00\00\00" | dd of=/dev/mtdblock2 bs=1 seek=24 count=4 conv=notrunc

sync
sync
sync
