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
#      same /tmp/h264_{high,low}_fifo FIFOs h264grabber used - plus, when audio is
#      on, /tmp/aac_audio_fifo from the mic (rRTSPServer/recorder unchanged),
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

# --- 3. rRTSPServer params ---------------------------------------------------
# One fork-free batch read (the old form forked ~8 get_config subshells, several
# on the SAME key). USER pre-cleared: it exists in the environment.
USER=""; PASSWORD=""; PORT=""; STREAM=""; ENABLED=""
AUDIO=""; AUDIO_QUALITY=""; AUDIO_NR_LEVEL=""
load_config services.rtsp USER PASSWORD PORT STREAM ENABLED \
                          AUDIO AUDIO_QUALITY AUDIO_NR_LEVEL
RRTSP_RES=$STREAM
case "$PORT" in
    ''|*[!0-9]*) RRTSP_PORT=554 ;;
    *) RRTSP_PORT=$PORT ;;
esac
RRTSP_USER=""; RRTSP_PWD=""
[ -n "$USER" ] && RRTSP_USER="-u $USER"
[ -n "$PASSWORD" ] && RRTSP_PWD="-w $PASSWORD"
RTSP_ENABLED=$ENABLED

# Forward audio (mic -> AAC): campipe captures AI, encodes AAC-LC and writes ADTS
# frames to /tmp/aac_audio_fifo, which is the FIFO rRTSPServer's audio track reads.
# AUDIO_QUALITY picks the mic sample rate - note this is the WHOLE inner codec's
# rate (one I2S clock for ADC and DAC), so it also becomes the speaker rate;
# campipe resamples the 8kHz backchannel up when needed.
# AUDIO names the codec. "yes" is the legacy spelling of "aac" (config files
# written before the codec became explicit), still honoured here and by
# rRTSPServer. g711 is 8kHz-only by definition, so campipe ignores AUDIO_QUALITY
# for it; note also that g711 cannot be muxed into MP4, so recordings go
# video-only (see record.sh).
case "$AUDIO" in
    g711|g711u) C_AUDIO=g711 ;;
    yes|aac)    C_AUDIO=aac ;;
    *)          C_AUDIO=off ;;
esac
case "$AUDIO_QUALITY" in
    high) C_AUDIO_RATE=16000 ;;
    *)    C_AUDIO_RATE=8000 ;;
esac
# ANR intensity, 0 = noise reduction off. Non-numeric or out of range -> off.
case "$AUDIO_NR_LEVEL" in
    ''|*[!0-9]*) C_AUDIO_NR=0 ;;
    *)           C_AUDIO_NR=$AUDIO_NR_LEVEL ;;
esac
[ "$C_AUDIO_NR" -gt 25 ] 2>/dev/null && C_AUDIO_NR=25
# rRTSPServer only advertises an audio track when campipe is actually producing
# one - otherwise the SDP promises audio the stream never carries.
RRTSP_AUDIO=no
[ "$C_AUDIO" != "off" ] && RRTSP_AUDIO=$C_AUDIO

# Motion detection: campipe runs the IVE detector when CAMPIPE_MD=yes and signals
# start/stop via the /tmp/ipc marker file (mqttv4 + onvif_notify_server watch it).
# MIC rides the same bus in the other direction (see below).
# Pre-clear MOTION_DETECTION/SENSITIVITY (generic names, may be in the env).
MOTION_DETECTION=""; SENSITIVITY=""; MIC=""
load_config camera MOTION_DETECTION SENSITIVITY MIC
C_MD=$MOTION_DETECTION
case "$SENSITIVITY" in low|medium|high) C_MD_SENS=$SENSITIVITY ;; *) C_MD_SENS=low ;; esac

# The event-bus dir must exist before onvif_notify_server starts (it aborts if the
# watched dir is missing) and before campipe writes the marker. Cheap + idempotent.
mkdir -p /tmp/ipc

# Seed the mic-mute marker from config. /tmp is tmpfs, so the marker is gone after
# a reboot and campipe would otherwise come up live regardless of camera.MIC.
# Live changes arrive via `ipc_cmd -I`, which maintains the same file.
if [ "$MIC" = "no" ] ; then
    : > /tmp/ipc/mic_off
else
    rm -f /tmp/ipc/mic_off
fi

# Speaker (audio out): the amp-enable + DAC level are board-specific, so look them
# up in the per-model audio_hw.conf table. When the model is mapped, campipe brings
# up AO, enables the amp, and plays PCM written to /tmp/audio_out_fifo; unmapped
# model -> empty AMP_ON -> campipe leaves audio out (and the speaker) alone.
AMP_ON=""; AMP_OFF=""; DAC_VOL=""
if [ -f /home/yi-hack/extra/script/audio_hw.conf ] ; then
    . /home/yi-hack/extra/script/audio_hw.conf
    audio_hw "$MODEL_SUFFIX" || { AMP_ON=""; AMP_OFF=""; DAC_VOL=""; }
fi

# Two-way audio (ONVIF backchannel): rRTSPServer receives the client's G.711
# voice and writes PCM to /tmp/audio_out_fifo, which campipe's AO plays.
#
# The speaker mapping IS the switch - there is deliberately no separate config
# toggle. On a model with no mapped amp nothing could play the audio anyway, and
# on one that has it the backchannel costs nothing until a client SETUPs the
# track (the AO thread runs off AMP_ON regardless, and the per-session receive
# state is built at SETUP), so an off position would only ever hide a working
# feature behind a setting nobody finds.
#
# Note this rides on the RTSP stream's own access control: with USER/PASSWORD
# empty the stream is unauthenticated, and so is the talk-back with it.
RRTSP_BACKCHANNEL=""
[ -n "$AMP_ON" ] && RRTSP_BACKCHANNEL="-b yes"

# Which FIFO carries the forward audio track, and the wait for it. rRTSPServer
# decides ONCE at startup whether that track exists - it stats the FIFO and
# disables audio if it is missing - so if it wins the race against campipe the
# stream stays silent for the whole life of the process, and nothing restarts it
# (the supervisor only reacts to a process that DIED). campipe creates the FIFO
# late, from the AI thread, after the full ISP/VI/VPSS/VENC bring-up, so 3 seconds
# is not a safe assumption; wait for the FIFO itself instead of for a duration.
case "$C_AUDIO" in
    aac)  AUDIO_FIFO=/tmp/aac_audio_fifo ;;
    g711) AUDIO_FIFO=/tmp/g711_audio_fifo ;;
    *)    AUDIO_FIFO="" ;;
esac

# Bounded, because audio may never arrive - a codec that fails to initialise, an
# unmapped model - and a video stream is much better than no stream at all.
wait_audio_fifo() {
    [ -z "$AUDIO_FIFO" ] && return 0
    _waf_i=0
    while [ ! -p "$AUDIO_FIFO" ] && [ $_waf_i -lt 30 ] ; do
        sleep 1
        _waf_i=$((_waf_i+1))
    done
    if [ -p "$AUDIO_FIFO" ] ; then
        [ $_waf_i -gt 0 ] && log "waited ${_waf_i}s for $AUDIO_FIFO"
    else
        log "WARNING: $AUDIO_FIFO not created after ${_waf_i}s - starting rRTSPServer without audio"
    fi
    return 0
}

# --- 4. supervise (no reboot) -----------------------------------------------
log "supervisor loop: vblk=$C_VBLK ldc=$C_LDC md=$C_MD sens=$C_MD_SENS ao=${AMP_ON:+on} ai=$C_AUDIO/${C_AUDIO_RATE}Hz/nr$C_AUDIO_NR rtsp=$RTSP_ENABLED res=$RRTSP_RES port=$RRTSP_PORT talk=${RRTSP_BACKCHANNEL:+on}"
while : ; do
    if ! pidof campipe >/dev/null 2>&1 ; then
        # Take rRTSPServer down WITH campipe. campipe recreates every FIFO it owns
        # on startup - unlink() then mkfifo(), video included - so an rRTSPServer
        # that outlived the crash keeps its fds on the OLD, now-unlinked inodes and
        # never sees another frame, while still answering pidof and so never being
        # restarted by the branch below. The whole stream stays dead until someone
        # reboots the camera by hand: there is no watchdog to do it here, because
        # wd_rtsp.sh - the one that reboots on a dead rmm - is deliberately not
        # started in native mode. Killing it now costs one restart cycle and the
        # next iteration brings it back against the new FIFOs.
        if pidof rRTSPServer >/dev/null 2>&1 ; then
            log "campipe gone: stopping rRTSPServer too (its FIFOs are about to be recreated)"
            killall -q rRTSPServer
        fi
        log "starting campipe (VBLK=$C_VBLK LDC=$C_LDC MD=$C_MD SENS=$C_MD_SENS AO=${AMP_ON:+on} AI=$C_AUDIO)"
        CAMPIPE_VBLK=$C_VBLK CAMPIPE_LDC=$C_LDC CAMPIPE_MD=$C_MD CAMPIPE_MD_SENS=$C_MD_SENS \
            CAMPIPE_AMP_ON="$AMP_ON" CAMPIPE_AMP_OFF="$AMP_OFF" CAMPIPE_DAC_VOL="$DAC_VOL" \
            CAMPIPE_AUDIO="$C_AUDIO" CAMPIPE_AUDIO_RATE="$C_AUDIO_RATE" \
            CAMPIPE_AUDIO_NR="$C_AUDIO_NR" \
            "$CAMPIPE" >> "$LOG_FILE" 2>&1 &
        sleep 3
    fi
    if [ "$RTSP_ENABLED" = "yes" ] && ! pidof rRTSPServer >/dev/null 2>&1 ; then
        wait_audio_fifo
        log "starting rRTSPServer (res=$RRTSP_RES port=$RRTSP_PORT audio=$RRTSP_AUDIO talk=${RRTSP_BACKCHANNEL:+on})"
        rRTSPServer -r "$RRTSP_RES" -a "$RRTSP_AUDIO" $RRTSP_BACKCHANNEL -p "$RRTSP_PORT" $RRTSP_USER $RRTSP_PWD >> "$LOG_FILE" 2>&1 &
    fi
    sleep 10
done
