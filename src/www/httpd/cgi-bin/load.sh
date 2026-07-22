#!/bin/sh

# 6.0.1

# Conf
CONF_FILE="etc/camera.conf"

. /home/yi-hack/base/script/get_config.sh

# Files
TMPOUT=/tmp/config.tar.bz2.dl
TMPDIR=/tmp/workdir.tmp
TMPOUTbz2=$TMPDIR/config.tar.bz2
TMPOUTtar=$TMPDIR/config.tar

# Cleaning
rm -f $TMPOUT
rm -f $TMPOUTbz2
rm -f $TMPOUTtar
rm -rf $TMPDIR

mkdir -p $TMPDIR

# backups now include services/*.conf too - allow up to 64 KB
if [ $CONTENT_LENGTH -gt 65536 ]; then
    exit
fi

if [ "$REQUEST_METHOD" = "POST" ]; then
    cat >$TMPOUT

    # Get the line count
    LINES=$(grep -c "" $TMPOUT)

    touch $TMPOUTbz2
    l=1
    LENSKIP=0

    # Process post data removing head and tail
    while true; do
        if [ $l -eq 1 ]; then
            ROW=`sed -n "${l}p" $TMPOUT`
            BOUNDARY=${#ROW}
            BOUNDARY=$((BOUNDARY+1))
            LENSKIPSTART=$BOUNDARY
            LENSKIPEND=$BOUNDARY
        elif [ $l -le 4 ]; then
            ROW=`sed -n "${l}p" $TMPOUT`
            ROWLEN=${#ROW}
            LENSKIPSTART=$((LENSKIPSTART+ROWLEN+1))
        elif [ \( $l -gt 4 \) -a \( $l -lt $LINES \) ]; then
            ROW=`sed -n "${l}p" $TMPOUT`
        else
            break
        fi
        l=$((l+1))
    done
fi

# Extract tar.bz2 file
LEN=$((CONTENT_LENGTH-LENSKIPSTART-LENSKIPEND+2))
dd if=$TMPOUT of=$TMPOUTbz2 bs=1 skip=$LENSKIPSTART count=$LEN >/dev/null 2>&1
cd $TMPDIR
bzip2 -d $TMPOUTbz2
tar xvf $TMPOUTtar >/dev/null 2>&1
RES=$?

# Version gate: refuse a backup from a different MAJOR.MINOR firmware (a config
# written for another baseline can carry renamed/removed keys). Backups without
# the marker (pre-6.0.x) are accepted as-is.
GATE_MSG=""
if [ $RES -eq 0 ] && [ -f backup_version ]; then
    CUR_MM=$(cut -d'_' -f1 /home/yi-hack/version | cut -d. -f1,2)
    BAK_MM=$(cut -d'_' -f1 backup_version | cut -d. -f1,2)
    if [ -n "$BAK_MM" ] && [ "$BAK_MM" != "$CUR_MM" ]; then
        RES=1
        GATE_MSG="Backup is from firmware $BAK_MM, this camera runs $CUR_MM - not restored."
    fi
fi

# Verify result of tar.bz2 command and copy files to destination
if [ $RES -eq 0 ]; then
    if [ \( -f "system.conf" \) -a \( -f "camera.conf" \) ]; then
        mv -f *.conf /home/yi-hack/config/
        chmod 0644 /home/yi-hack/config/*.conf
        # per-service configs (present in backups taken from 6.0.x onward)
        if [ -d services ]; then
            # No 2>/dev/null: this restores the user's configuration, and a
            # silent failure here leaves the camera on a half-restored config.
            for f in services/*.conf; do
                [ -e "$f" ] || break
                mv -f "$f" /home/yi-hack/config/services/ || echo "load[ERROR]: cannot restore $f" >&2
            done
            chmod 0644 /home/yi-hack/config/services/*.conf
        fi
        if [ -f hostname ]; then
            mv -f hostname /home/yi-hack/config/
            chmod 0644 /home/yi-hack/config/hostname
        fi
        RES=0
    else
        RES=1
    fi
fi

# Cleaning
cd ..
rm -rf $TMPDIR
rm -f $TMPOUT
rm -f $TMPOUTbz2

# Print response
printf "Content-type: text/html\r\n\r\n"
if [ $RES -eq 0 ]; then
    printf "Upload completed successfully, restart your camera\r\n"
elif [ -n "$GATE_MSG" ]; then
    printf "%s\r\n" "$GATE_MSG"
else
    printf "Upload failed\r\n"
fi

if [ ! -f "/home/yi-hack/config/camera.conf" ]; then
    exit
fi

# Set camera settings (one batch config read, no get_config subshells)
load_config camera SWITCH_ON SAVE_VIDEO_ON_MOTION SENSITIVITY LED IR ROTATE

if [[ $SWITCH_ON == "no" ]] ; then
    ipc_cmd -t off
else
    ipc_cmd -t on
fi

if [[ $SAVE_VIDEO_ON_MOTION == "no" ]] ; then
    ipc_cmd -v always
else
    ipc_cmd -v detect
fi

ipc_cmd -s $SENSITIVITY

if [[ $LED == "no" ]] ; then
    ipc_cmd -l off
else
    ipc_cmd -l on
fi

if [[ $IR == "no" ]] ; then
    ipc_cmd -i off
else
    ipc_cmd -i on
fi

if [[ $ROTATE == "no" ]] ; then
    ipc_cmd -r off
else
    ipc_cmd -r o
fi
