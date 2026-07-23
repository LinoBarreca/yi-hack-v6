#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# Native MPP media supervisor (PIPELINE=online|offline). Invoked ONLY from
# system.sh when pipeline.MODE selects the native pipeline, MODEL=y20, and the
# assets (SDK kernel modules + campipe) exist. Does three things:
#   1. reloads the HiSilicon SDK kernel modules so they match campipe's SDK build
#      (campipe links the 1.0.4.0 MPP libs; the stock 1.0.4.1 modules make
#      HI_MPI_ISP_MemInit fail -> a consistent SDK stack is required),
#   2. launches campipe, which drives sensor->ISP->VI->VPSS->VENC and writes the
#      same /tmp/h264_{high,low}_fifo FIFOs h264grabber used (rRTSPServer/recorder
#      unchanged),
#   3. supervises campipe + rRTSPServer, restarting either if it dies - WITHOUT
#      rebooting (unlike wd_rtsp.sh, which reboots on rmm-gone).
#
# WARNING - module reload safety: `load3518e -a` (teardown) HARD-HANGS the SoC if
# a live MPP pipeline is running. It is safe here ONLY because native mode never
# starts the stock stack (system.sh skips rmm/dispatch/...), so nothing holds an
# MPP device when we tear down the stock modules that init.sh loaded. Never call
# this while stock is running.
#
# Args: MODE(online|offline)  LDC(0..100)  KO_DIR(load3518e dir)  CAMPIPE(binary)

MODE="$1"
LDC="$2"
KO_DIR="$3"
CAMPIPE="$4"

script_name=$(basename -- "$0")
if pidof "$script_name" -o $$ >/dev/null 2>&1 ; then
    echo "Already running - quitting"
    exit 1
fi

. /home/yi-hack/base/script/get_config.sh
read MODEL_SUFFIX < /home/app/.camver

# Routed through the output/log view (output.LOG matrix); on NO it symlinks to
# /dev/null, so no separate switch is needed here.
LOG_FILE="/home/yi-hack/output/log/native_pipeline.log"
export LD_LIBRARY_PATH="/lib:/home/lib:/home/app/locallib:/home/hisiko/hisilib:/home/base/lib:/home/yi-hack/extra/lib"
export PATH="$PATH:/home/app/localbin:/home/base/tools"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }

# --- 1. reload SDK kernel modules -------------------------------------------
# offline enables VI LDC (lens distortion correction); online is lowest
# latency/RAM but LDC is unsupported by the VIU driver in that mode.
OFFLINE=""
[ "$MODE" = "offline" ] && OFFLINE="-offline"
log "native start: mode=$MODE ldc=$LDC ko=$KO_DIR bin=$CAMPIPE"

# Stage the modules into tmpfs and insmod from there. The payload KO_DIR is on a
# read-only CIFS mount; loading .ko straight off CIFS is untested (mmap/latency),
# so we copy to RAM first (~3MB, /tmp is 16MB tmpfs) and load locally - robust
# regardless of where the payload lives. Skipped if KO_DIR is already local.
KO_RUN="$KO_DIR"
case "$KO_DIR" in
    /tmp/*) : ;;   # already on tmpfs/SD-local - use as-is
    *)
        KO_RUN=/tmp/native-ko
        rm -rf "$KO_RUN"; mkdir -p "$KO_RUN"
        if cp -a "$KO_DIR"/. "$KO_RUN"/ 2>>"$LOG_FILE" ; then
            log "staged modules to tmpfs ($KO_RUN)"
        else
            log "WARNING - tmpfs staging failed, loading directly from $KO_DIR"
            KO_RUN="$KO_DIR"
        fi
        ;;
esac

log "reloading SDK modules ($MODE) from $KO_RUN ..."
( cd "$KO_RUN" && ./load3518e -a -sensor ov9732 -osmem 34 -total 64 $OFFLINE ) >> "$LOG_FILE" 2>&1
# Stock F22 sensor clock (SDK loader writes a different value); libpthread needs
# LD_LIBRARY_PATH, already exported above.
himm 0x2003002c 0x1c4001 >/dev/null 2>&1
log "modules reloaded (hi3518e count = $(lsmod | grep -c hi3518e))"

# --- 2. campipe env per mode ------------------------------------------------
# VB pool depth: offline needs 5 (VI->DDR->VPSS round-trip + LDC), online 3.
# LDC only meaningful offline; validated ranges baked into campipe defaults.
if [ "$MODE" = "offline" ] ; then
    case "$LDC" in ''|*[!0-9]*) LDC=0 ;; esac
    [ "$LDC" -gt 100 ] 2>/dev/null && LDC=100
    C_VBLK=5
    C_LDC="$LDC"
else
    C_VBLK=3
    C_LDC=0
fi

# --- 3. rRTSPServer params (audio forced OFF - campipe is video-only) --------
# One fork-free batch read (the old form forked ~8 get_config subshells, several
# on the SAME key). USER pre-cleared: it exists in the environment.
USER=""; PASSWORD=""; PORT=""; STREAM=""; ENABLED=""
load_config services.rtsp USER PASSWORD PORT STREAM ENABLED
RRTSP_RES=$STREAM
case "$PORT" in
    ''|*[!0-9]*) RRTSP_PORT=554 ;;
    *) RRTSP_PORT=$PORT ;;
esac
RRTSP_USER=""; RRTSP_PWD=""
[ -n "$USER" ] && RRTSP_USER="-u $USER"
[ -n "$PASSWORD" ] && RRTSP_PWD="-w $PASSWORD"
RTSP_ENABLED=$ENABLED

# --- 4. supervise (no reboot) -----------------------------------------------
log "supervisor loop: vblk=$C_VBLK ldc=$C_LDC rtsp=$RTSP_ENABLED res=$RRTSP_RES port=$RRTSP_PORT"
while : ; do
    if ! pidof campipe >/dev/null 2>&1 ; then
        log "starting campipe (VBLK=$C_VBLK LDC=$C_LDC)"
        CAMPIPE_VBLK=$C_VBLK CAMPIPE_LDC=$C_LDC "$CAMPIPE" >> "$LOG_FILE" 2>&1 &
        sleep 3
    fi
    if [ "$RTSP_ENABLED" = "yes" ] && ! pidof rRTSPServer >/dev/null 2>&1 ; then
        log "starting rRTSPServer (res=$RRTSP_RES port=$RRTSP_PORT, audio off)"
        rRTSPServer -r "$RRTSP_RES" -a no -p "$RRTSP_PORT" $RRTSP_USER $RRTSP_PWD >> "$LOG_FILE" 2>&1 &
    fi
    sleep 10
done
