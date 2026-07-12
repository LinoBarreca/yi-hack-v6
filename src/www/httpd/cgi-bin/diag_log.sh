#!/bin/sh

# 6.0.1
#
# diag_log.sh - serve one diagnostic log/state dump, chosen from a WHITELIST
# (never from a client-supplied path). Used by the Diagnostics page.
#
#   ?name=list            -> JSON list of available entries
#   ?name=<id>            -> text/plain content
#   ?name=<id>&download=1 -> same, as attachment
#
# File-backed entries resolve through the output/log view (matrix output.LOG);
# command-backed entries run a fixed busybox command.

LOGDIR="/home/yi-hack/output/log"

NAME=""; DOWNLOAD=""
OIFS=$IFS; IFS='&'
for _kv in $QUERY_STRING; do
    case "$_kv" in
        name=*)     [ -n "$NAME" ] || NAME=$(printf '%s' "${_kv#*=}" | tr -cd 'a-z_0-9') ;;
        download=*) [ -n "$DOWNLOAD" ] || DOWNLOAD="${_kv#*=}" ;;
    esac
done
IFS=$OIFS

# id -> type:target   (file entries are relative to LOGDIR unless absolute)
entry() {
    case "$1" in
        boot)         echo "file:/dev/yi-boot.log" ;;
        dmesg)        echo "cmd:dmesg" ;;
        ps)           echo "cmd:ps w" ;;
        meminfo)      echo "cmd:cat /proc/meminfo" ;;
        mounts)       echo "cmd:mount" ;;
        df)           echo "cmd:df -h" ;;
        netstat)      echo "cmd:netstat -tuln" ;;
        wifi)         echo "cmd:iwconfig wlan0" ;;
        wd_rtsp)      echo "file:wd_rtsp.log" ;;
        onvif)        echo "file:onvif_simple_server.log" ;;
        onvif_notify) echo "file:onvif_notify_server.log" ;;
        wsd)          echo "file:wsd_simple_server.log" ;;
        stock_log)    echo "file:log.txt" ;;
        stock_alarm)  echo "file:debug_alarm.txt" ;;
        stock_p2p)    echo "file:debug_p2p.txt" ;;
        stock_oss)    echo "file:debug_oss.txt" ;;
        *)            echo "" ;;
    esac
}

ALL="boot dmesg ps meminfo mounts df netstat wifi wd_rtsp onvif onvif_notify wsd stock_log stock_alarm stock_p2p stock_oss"

if [ "$NAME" = "list" ] || [ -z "$NAME" ]; then
    printf "Content-type: application/json\r\n\r\n"
    printf '{"logs":['
    FIRST=1
    for id in $ALL; do
        E=$(entry "$id"); TYPE=${E%%:*}; TARGET=${E#*:}
        if [ "$TYPE" = "file" ]; then
            case "$TARGET" in /*) F="$TARGET" ;; *) F="$LOGDIR/$TARGET" ;; esac
            # skip missing files and the /dev/null links of output.LOG=NO
            [ -f "$F" ] || [ -c "$F" ] || continue
            [ "$(readlink "$F" 2>/dev/null)" = "/dev/null" ] && continue
        fi
        [ "$FIRST" = 1 ] || printf ','
        printf '"%s"' "$id"
        FIRST=0
    done
    printf ']}'
    exit 0
fi

E=$(entry "$NAME")
if [ -z "$E" ]; then
    printf "Status: 404 Not Found\r\nContent-type: text/plain\r\n\r\nunknown log '%s'\n" "$NAME"
    exit 0
fi

printf "Content-type: text/plain; charset=utf-8\r\n"
[ "$DOWNLOAD" = "1" ] && printf "Content-Disposition: attachment; filename=\"%s.txt\"\r\n" "$NAME"
printf "\r\n"

TYPE=${E%%:*}; TARGET=${E#*:}
if [ "$TYPE" = "cmd" ]; then
    $TARGET 2>&1
else
    case "$TARGET" in /*) F="$TARGET" ;; *) F="$LOGDIR/$TARGET" ;; esac
    if [ -e "$F" ]; then cat "$F"; else echo "(empty - $F not present)"; fi
fi
