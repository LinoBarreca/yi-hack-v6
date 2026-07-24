/*
 * campipe - native MPP media pipeline for yi-hack-v6 (Stage A: video).
 *
 * Owns the HiSilicon media pipeline directly instead of scraping rmm's output
 * from /tmp/view. Brings up sensor -> ISP -> VI -> VPSS -> VENC (using the
 * vendor SDK helpers in src/hisdk) and streams the encoded H.264 into the same
 * FIFOs rRTSPServer already consumes, so nothing downstream changes:
 *     VENC 0  H.264  1080p   -> /tmp/h264_high_fifo   (VPSS grp0 chn0)
 *     VENC 1  H.264  640x360 -> /tmp/h264_low_fifo    (VPSS grp0 chn1)
 * VENC channels 2/3 are the on-demand hardware JPEG snap channels (1080p /
 * 320x192), created idle and left for `hwsnap` to trigger exactly as it did
 * against rmm. This runs ONLY in place of rmm (never alongside it): the MMZ is
 * too small for two pipelines, and both would fight for the sensor.
 *
 * Stage A is video & lens distortion correction only
 * Stage B is IVE motion detection (MD) and audio out (AO) in PTT mode
 * Stage C is audio in (AI/AENC) and day/night actuation
 
 * Motion detection (IVE) lives here now (see md_thread): when CAMPIPE_MD=on a
 * hardware IVE motion detector runs on a dedicated downscaled VPSS channel and
 * signals start/stop by creating/removing the marker file /tmp/ipc/motion_alarm,
 * which mqttv4 (MQTT/HA) and onvif_notify_server (ONVIF) already watch via inotify
 * — the same file ipc2file writes in stock mode, so both consumers are unchanged.
 * The board bring-up (MPP .ko load, sensor pinmux/clock) is done by the startup
 * script before this runs, reusing the stock hisiko scripts.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <pthread.h>
#include <errno.h>
#include <dlfcn.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <poll.h>

#include "sample_comm.h"
#include "hi_ive.h"
#include "ivs_md.h"
#include "acodec.h"

/* ---- pipeline geometry (matches the stock y20 layout) ------------------- */
#define VPSS_GRP        0
#define CHN_HIGH        0          /* VENC chn + VPSS chn for the 1080p H.264 */
#define CHN_LOW         1          /* VENC chn + VPSS chn for the 640x360 H.264 */
#define VPSS_CHN_SNAP   2          /* 320x192 VPSS chn feeding the small JPEG  */
#define VPSS_CHN_MD     3          /* 320x192 VPSS chn feeding the IVE detector */
#define VENC_JPEG_HIGH  2          /* on-demand JPEG, fed by VPSS chn0 (1080p) */
#define VENC_JPEG_LOW   3          /* on-demand JPEG, fed by VPSS chn2 (320x192)*/

#define W_HIGH 1920
#define H_HIGH 1080
#define W_LOW  640
#define H_LOW  360
#define W_SNAP 320
#define H_SNAP 192
#define W_MD   320                 /* MD works on a downscaled grayscale frame  */
#define H_MD   192

#define FIFO_HIGH "/tmp/h264_high_fifo"
#define FIFO_LOW  "/tmp/h264_low_fifo"

/* Local event bus: the detector signals motion by creating this marker file and
 * clears it on stop. Consumers (mqttv4, onvif_notify_server) watch the dir with
 * inotify — identical to what ipc2file writes in stock mode. */
#define IPC_DIR       "/tmp/ipc"
#define MOTION_MARKER IPC_DIR "/motion_alarm"

/* Audio out (speaker): campipe plays PCM (8kHz/16-bit/mono, signed LE) written to
 * this FIFO through AO. The speaker-amp enable + DAC level are board-specific and
 * come from the per-model audio_hw.conf table via env (CAMPIPE_AMP_ON/_OFF /
 * CAMPIPE_DAC_VOL) - never hardcoded. AO is only brought up when CAMPIPE_AMP_ON is
 * set (i.e. the model is in the table and audio-out is enabled). */
#define AO_DEV      0
#define AO_CHN      0
#define AO_PTNUM    320          /* samples per frame (40 ms @ 8 kHz) */
#define FIFO_AUDIO  "/tmp/audio_out_fifo"

/* The y20 sensor is a SOI JXF22 (1080p25, DVP 10-bit, i2c 0x80/8-bit regs) —
 * identified by letting stock rmm probe it (it dlopens libsns_f22.so). The SDK
 * ships no F22 driver, so we reuse the stock plugin the same way rmm does:
 * dlopen + sensor_register_callback(). It resolves HI_MPI_{AE,AWB,ISP}_Sensor*
 * from our (statically linked) executable — hence -rdynamic in the Makefile. */
#define SNS_PLUGIN_DEFAULT "/home/app/locallib/libsns_f22.so"
#define SNS_FPS      25          /* F22 timing as its own init banner reports  */
#define SNS_BAYER    BAYER_BGGR  /* what stock rmm sets in ISP pub attr        */

#define F_SETPIPE_SZ (1024 + 7)

static VIDEO_NORM_E g_norm = VIDEO_ENCODING_MODE_PAL;   /* SAMPLE default */
static volatile int g_stop = 0;

static void *g_sns_handle;
static int (*g_sns_unreg)(void);

/* Override the SDK's static-lib sensor hooks (sample_comm_isp.o references
 * sensor_register_callback by name; defining it here wins at link time and no
 * libsns_*.a is linked at all). */
int sensor_register_callback(void)
{
    const char *lib = getenv("CAMPIPE_SNS_LIB");
    int (*reg)(void);

    if (!lib || !*lib)
        lib = SNS_PLUGIN_DEFAULT;
    g_sns_handle = dlopen(lib, RTLD_NOW | RTLD_GLOBAL);
    if (!g_sns_handle) {
        SAMPLE_PRT("dlopen %s failed: %s\n", lib, dlerror());
        return HI_FAILURE;
    }
    reg = (int (*)(void))dlsym(g_sns_handle, "sensor_register_callback");
    g_sns_unreg = (int (*)(void))dlsym(g_sns_handle, "sensor_unregister_callback");
    if (!reg) {
        SAMPLE_PRT("no sensor_register_callback in %s\n", lib);
        return HI_FAILURE;
    }
    SAMPLE_PRT("sensor plugin: %s\n", lib);
    return reg();
}

int sensor_unregister_callback(void)
{
    return g_sns_unreg ? g_sns_unreg() : HI_SUCCESS;
}

/* ISP bring-up for the F22: same call sequence as SAMPLE_COMM_ISP_Init /
 * stock rmm, but with the F22's real geometry (the sample's per-sensor pub
 * attr table has no F22 entry). */
static HI_S32 f22_isp_init(void)
{
    ALG_LIB_S lib;
    ISP_PUB_ATTR_S pub;
    ISP_WDR_MODE_S wdr;
    HI_S32 ret;

    if ((ret = sensor_register_callback()) != HI_SUCCESS)
        return ret;

    lib.s32Id = 0;
    strcpy(lib.acLibName, HI_AE_LIB_NAME);
    if ((ret = HI_MPI_AE_Register(0, &lib)) != HI_SUCCESS) {
        SAMPLE_PRT("AE_Register failed %#x\n", ret);
        return ret;
    }
    lib.s32Id = 0;
    strcpy(lib.acLibName, HI_AWB_LIB_NAME);
    if ((ret = HI_MPI_AWB_Register(0, &lib)) != HI_SUCCESS) {
        SAMPLE_PRT("AWB_Register failed %#x\n", ret);
        return ret;
    }
    lib.s32Id = 0;
    strcpy(lib.acLibName, HI_AF_LIB_NAME);
    if ((ret = HI_MPI_AF_Register(0, &lib)) != HI_SUCCESS) {
        SAMPLE_PRT("AF_Register failed %#x\n", ret);
        return ret;
    }
    if ((ret = HI_MPI_ISP_MemInit(0)) != HI_SUCCESS) {
        SAMPLE_PRT("ISP_MemInit failed %#x\n", ret);
        return ret;
    }
    wdr.enWDRMode = WDR_MODE_NONE;
    if ((ret = HI_MPI_ISP_SetWDRMode(0, &wdr)) != HI_SUCCESS) {
        SAMPLE_PRT("ISP_SetWDRMode failed %#x\n", ret);
        return ret;
    }
    memset(&pub, 0, sizeof(pub));
    pub.stWndRect.s32X = 0;
    pub.stWndRect.s32Y = 0;
    pub.stWndRect.u32Width  = W_HIGH;
    pub.stWndRect.u32Height = H_HIGH;
    pub.f32FrameRate = SNS_FPS;
    pub.enBayer = SNS_BAYER;
    if ((ret = HI_MPI_ISP_SetPubAttr(0, &pub)) != HI_SUCCESS) {
        SAMPLE_PRT("ISP_SetPubAttr failed %#x\n", ret);
        return ret;
    }
    if ((ret = HI_MPI_ISP_Init(0)) != HI_SUCCESS) {
        SAMPLE_PRT("ISP_Init failed %#x\n", ret);
        return ret;
    }
    return HI_SUCCESS;
}

/* VI+ISP start for the F22 (replaces SAMPLE_COMM_VI_StartVi, whose per-sensor
 * tables are all wrong-sized for it). Same step order as the sample:
 * MIPI/CMOS attr -> ISP init -> ISP run thread -> VI dev -> VI chn. The dev
 * attr is the SDK's OV9732 DC one (identical interface: DC, 1mux, 10-bit mask
 * 0xFFC0000, progressive, YUYV, ISP path — verified against a running stock
 * rmm in /proc/umap/vi) widened to the F22's 1920x1080. */
static HI_S32 f22_start_vi_isp(SAMPLE_VI_CONFIG_S *vi)
{
    extern VI_DEV_ATTR_S DEV_ATTR_OV9732_DC_720P_BASE;
    VI_DEV_ATTR_S dev;
    RECT_S  cap  = { 0, 0, W_HIGH, H_HIGH };
    SIZE_S  size = { W_HIGH, H_HIGH };
    HI_S32 ret;

    if ((ret = SAMPLE_COMM_VI_StartMIPI(vi)) != HI_SUCCESS) {
        SAMPLE_PRT("StartMIPI failed %#x\n", ret);
        return ret;
    }
    if ((ret = f22_isp_init()) != HI_SUCCESS)
        return ret;
    if ((ret = SAMPLE_COMM_ISP_Run()) != HI_SUCCESS) {
        SAMPLE_PRT("ISP_Run failed %#x\n", ret);
        return ret;
    }

    memcpy(&dev, &DEV_ATTR_OV9732_DC_720P_BASE, sizeof(dev));
    dev.stDevRect = cap;
    dev.stSynCfg.stTimingBlank.u32HsyncAct  = W_HIGH;
    dev.stSynCfg.stTimingBlank.u32VsyncVact = H_HIGH;
    if ((ret = HI_MPI_VI_SetDevAttr(0, &dev)) != HI_SUCCESS) {
        SAMPLE_PRT("VI_SetDevAttr failed %#x\n", ret);
        return ret;
    }
    if ((ret = HI_MPI_VI_EnableDev(0)) != HI_SUCCESS) {
        SAMPLE_PRT("VI_EnableDev failed %#x\n", ret);
        return ret;
    }
    if ((ret = SAMPLE_COMM_VI_StartChn(0, &cap, &size, vi)) != HI_SUCCESS) {
        SAMPLE_PRT("VI_StartChn failed %#x\n", ret);
        return ret;
    }

    /* Lens distortion correction. The fisheye lens needs the same barrel
     * correction the stock pipeline applies via HI_MPI_VI_SetLDCAttr on the VI
     * chn (rmm: enViewType=ALL, center offsets 0, s32Ratio = app slider, which
     * the app clamps to [0,100]). Without this our stream is heavily distorted.
     * Ratio comes from config (default here; wired to a config key later).
     *
     * IMPORTANT: only touch LDC when a correction is actually requested. VI LDC
     * is UNSUPPORTED in VI-VPSS online mode (the VIU driver's ioctl prefilter
     * rejects it with 0xa0108008 when vi_vpss_online != 0). Calling it at all in
     * online mode would abort bring-up, so ratio==0 must skip the call entirely
     * — that keeps PIPELINE=online working (LDC off, lowest latency). */
    {
        int ratio = 0;
        const char *env = getenv("CAMPIPE_LDC");
        if (env) ratio = atoi(env);
        if (ratio < 0) ratio = 0;
        if (ratio > 500) ratio = 500;

        if (ratio > 0) {
            VI_LDC_ATTR_S ldc;
            memset(&ldc, 0, sizeof(ldc));
            ldc.bEnable = HI_TRUE;
            ldc.stAttr.enViewType = LDC_VIEW_TYPE_ALL;
            ldc.stAttr.s32CenterXOffset = 0;
            ldc.stAttr.s32CenterYOffset = 0;
            ldc.stAttr.s32Ratio = ratio;
            if ((ret = HI_MPI_VI_SetLDCAttr(0, &ldc)) != HI_SUCCESS) {
                SAMPLE_PRT("VI_SetLDCAttr(ratio=%d) failed %#x (offline mode required)\n",
                           ratio, ret);
                return ret;
            }
            SAMPLE_PRT("LDC ratio=%d enabled\n", ratio);
        }
    }
    return HI_SUCCESS;
}

/* One streaming thread per H.264 channel: drain VENC and write NAL units to a
 * FIFO, mirroring what `h264grabber -f` used to produce. */
typedef struct {
    VENC_CHN chn;
    const char *fifo;
    int pipe_sz;
} stream_ctx_t;

static void on_signal(int sig)
{
    (void)sig;
    g_stop = 1;
}

/* Tunables via env (KB), for the offline memory-budget sweep. Return the env
 * value in bytes if set and >0, else the fallback. */
static HI_U32 env_kb(const char *name, HI_U32 fallback_bytes)
{
    const char *e = getenv(name);
    if (e && *e) {
        long kb = atol(e);
        if (kb > 0)
            return (HI_U32)kb * 1024;
    }
    return fallback_bytes;
}

/* Create + start one H.264 VENC channel with explicit dimensions (the stock
 * 640x360 low stream is not a standard PIC_SIZE_E, so we build the attr by
 * hand instead of via SAMPLE_COMM_VENC_Start) and bind it to its VPSS chn. */
static HI_S32 start_h264(VENC_CHN chn, VPSS_CHN vpss_chn, HI_U32 w, HI_U32 h,
                         HI_U32 bitrate_kbps, HI_U32 framerate)
{
    VENC_CHN_ATTR_S attr;
    VENC_ATTR_H264_CBR_S cbr;
    HI_S32 ret;

    memset(&attr, 0, sizeof(attr));
    attr.stVeAttr.enType = PT_H264;
    attr.stVeAttr.stAttrH264e.u32MaxPicWidth  = w;
    attr.stVeAttr.stAttrH264e.u32MaxPicHeight = h;
    attr.stVeAttr.stAttrH264e.u32PicWidth     = w;
    attr.stVeAttr.stAttrH264e.u32PicHeight    = h;
    /* Stream (bitstream output) buffer. Only needs to hold a few frames of
     * backlog; a 1080p I-frame is ~100-250KB (stock sizes h264e0_Str at 204KB).
     * w*h/4 (=~506KB at 1080p) leaves ~2x margin; validated on 1.0.4.0 down to
     * 256KB. Small low stream keeps its (already tiny) w*h. Env overrides for
     * the offline memory sweep. */
    attr.stVeAttr.stAttrH264e.u32BufSize      =
        env_kb(chn == CHN_HIGH ? "CAMPIPE_H264HI_KB" : "CAMPIPE_H264LO_KB",
               chn == CHN_HIGH ? w * h / 4 : w * h);
    attr.stVeAttr.stAttrH264e.u32Profile      = 1;               /* main       */
    attr.stVeAttr.stAttrH264e.bByFrame        = HI_TRUE;
    attr.stVeAttr.stAttrH264e.u32BFrameNum    = 0;
    attr.stVeAttr.stAttrH264e.u32RefNum       = 1;

    attr.stRcAttr.enRcMode = VENC_RC_MODE_H264CBR;
    memset(&cbr, 0, sizeof(cbr));
    cbr.u32Gop            = framerate * 2;      /* 2s GOP */
    cbr.u32StatTime       = 1;
    cbr.u32SrcFrmRate     = framerate;
    cbr.fr32DstFrmRate    = framerate;
    cbr.u32BitRate        = bitrate_kbps;
    cbr.u32FluctuateLevel = 0;
    attr.stRcAttr.stAttrH264Cbr = cbr;

    ret = HI_MPI_VENC_CreateChn(chn, &attr);
    if (ret != HI_SUCCESS) {
        SAMPLE_PRT("CreateChn(%d) failed %#x\n", chn, ret);
        return ret;
    }
    ret = HI_MPI_VENC_StartRecvPic(chn);
    if (ret != HI_SUCCESS) {
        SAMPLE_PRT("StartRecvPic(%d) failed %#x\n", chn, ret);
        return ret;
    }
    ret = SAMPLE_COMM_VENC_BindVpss(chn, VPSS_GRP, vpss_chn);
    if (ret != HI_SUCCESS) {
        SAMPLE_PRT("BindVpss(venc %d <- vpss %d) failed %#x\n", chn, vpss_chn, ret);
        return ret;
    }
    return HI_SUCCESS;
}

/* Create an on-demand JPEG snap channel (idle: no StartRecvPic) bound to a VPSS
 * chn. hwsnap does StartRecvPicEx/GetStream on it, same as against rmm. */
static HI_S32 start_jpeg(VENC_CHN chn, VPSS_CHN vpss_chn, HI_U32 w, HI_U32 h)
{
    VENC_CHN_ATTR_S attr;
    HI_S32 ret;

    memset(&attr, 0, sizeof(attr));
    attr.stVeAttr.enType = PT_JPEG;
    attr.stVeAttr.stAttrJpeg.u32MaxPicWidth  = w;
    attr.stVeAttr.stAttrJpeg.u32MaxPicHeight = h;
    attr.stVeAttr.stAttrJpeg.u32PicWidth     = w;
    attr.stVeAttr.stAttrJpeg.u32PicHeight    = h;
    /* JPEG output buffer. A 1080p JPEG is ~300-350KB (measured); stock sizes
     * Jpege2 at 1036KB. w*h/2 (=~1013KB at 1080p) gives ~3x margin for busy
     * scenes; validated on 1.0.4.0 down to 512KB. Tiny 320x192 snap keeps its
     * (small) w*h*2. Env overrides for the sweep. */
    attr.stVeAttr.stAttrJpeg.u32BufSize      =
        env_kb(w > 1000 ? "CAMPIPE_JPEGHI_KB" : "CAMPIPE_JPEGLO_KB",
               w > 1000 ? w * h / 2 : w * h * 2);
    attr.stVeAttr.stAttrJpeg.bByFrame        = HI_TRUE;
    attr.stVeAttr.stAttrJpeg.bSupportDCF     = HI_FALSE;

    ret = HI_MPI_VENC_CreateChn(chn, &attr);
    if (ret != HI_SUCCESS) {
        SAMPLE_PRT("CreateChn(jpeg %d) failed %#x\n", chn, ret);
        return ret;
    }
    ret = SAMPLE_COMM_VENC_BindVpss(chn, VPSS_GRP, vpss_chn);
    if (ret != HI_SUCCESS) {
        SAMPLE_PRT("BindVpss(jpeg %d <- vpss %d) failed %#x\n", chn, vpss_chn, ret);
        return ret;
    }
    return HI_SUCCESS;
}

static void *stream_thread(void *arg)
{
    stream_ctx_t *ctx = arg;
    VENC_CHN chn = ctx->chn;
    int venc_fd, fifo_fd = -1;
    HI_S32 ret;

    unlink(ctx->fifo);
    if (mkfifo(ctx->fifo, 0666) < 0 && errno != EEXIST) {
        SAMPLE_PRT("mkfifo %s failed: %s\n", ctx->fifo, strerror(errno));
        return NULL;
    }

    venc_fd = HI_MPI_VENC_GetFd(chn);
    if (venc_fd < 0) {
        SAMPLE_PRT("GetFd(%d) failed %#x\n", chn, venc_fd);
        return NULL;
    }

    while (!g_stop) {
        fd_set fds;
        struct timeval tv = { .tv_sec = 1, .tv_usec = 0 };
        VENC_CHN_STAT_S stat;
        VENC_STREAM_S stream;
        HI_U32 i;

        /* (Re)open the FIFO for writing; blocks until a reader (rRTSPServer)
         * attaches. O_NONBLOCK so we can keep draining VENC meanwhile. */
        if (fifo_fd < 0) {
            fifo_fd = open(ctx->fifo, O_WRONLY | O_NONBLOCK);
            if (fifo_fd >= 0)
                fcntl(fifo_fd, F_SETPIPE_SZ, ctx->pipe_sz);
        }

        FD_ZERO(&fds);
        FD_SET(venc_fd, &fds);
        ret = select(venc_fd + 1, &fds, NULL, NULL, &tv);
        if (ret <= 0)
            continue;

        ret = HI_MPI_VENC_Query(chn, &stat);
        if (ret != HI_SUCCESS || stat.u32CurPacks == 0)
            continue;

        memset(&stream, 0, sizeof(stream));
        stream.pstPack = malloc(sizeof(VENC_PACK_S) * stat.u32CurPacks);
        if (!stream.pstPack)
            continue;
        stream.u32PackCount = stat.u32CurPacks;

        ret = HI_MPI_VENC_GetStream(chn, &stream, HI_TRUE);
        if (ret != HI_SUCCESS) {
            free(stream.pstPack);
            continue;
        }

        if (fifo_fd >= 0) {
            for (i = 0; i < stream.u32PackCount; i++) {
                VENC_PACK_S *p = &stream.pstPack[i];
                HI_U8 *data = p->pu8Addr + p->u32Offset;
                HI_U32 len = p->u32Len - p->u32Offset;
                while (len > 0) {
                    ssize_t n = write(fifo_fd, data, len);
                    if (n > 0) { data += n; len -= n; continue; }
                    if (n < 0 && (errno == EAGAIN)) { usleep(1000); continue; }
                    /* reader went away: drop the FIFO and wait for a new one */
                    close(fifo_fd);
                    fifo_fd = -1;
                    break;
                }
                if (fifo_fd < 0)
                    break;
            }
        }

        HI_MPI_VENC_ReleaseStream(chn, &stream);
        free(stream.pstPack);
    }

    if (fifo_fd >= 0)
        close(fifo_fd);
    return NULL;
}

/* ---- IVE hardware motion detection -------------------------------------- */
/* Sensitivity -> (SAD threshold, min blob area). u16SadThr is the per-block sum
 * of absolute differences that counts as "changed": a HIGHER threshold needs a
 * bigger change, so it is LESS sensitive. min_area is the summed area (in the
 * SAD/CCL map) below which a detection is ignored, filtering out tiny flicker.
 * The three presets are starting points meant to be tuned on hardware. */
typedef struct { int sad_thr; int min_area; } md_sens_t;
static md_sens_t md_sens_for(const char *s)
{
    if (s && !strcmp(s, "high"))   return (md_sens_t){ 150, 8  };
    if (s && !strcmp(s, "medium")) return (md_sens_t){ 350, 15 };
    return (md_sens_t){ 600, 25 };   /* "low" / default */
}

/* Wrap a VPSS frame's Y plane as a U8C1 IVE image (no copy — the IVE engine
 * reads the physical address directly). */
static void frame_to_ive_y(VIDEO_FRAME_INFO_S *f, IVE_SRC_IMAGE_S *img)
{
    memset(img, 0, sizeof(*img));
    img->enType        = IVE_IMAGE_TYPE_U8C1;
    img->u32PhyAddr[0] = f->stVFrame.u32PhyAddr[0];
    img->pu8VirAddr[0] = (HI_U8 *)f->stVFrame.pVirAddr[0];
    img->u16Stride[0]  = (HI_U16)f->stVFrame.u32Stride[0];
    img->u16Width      = W_MD;
    img->u16Height     = H_MD;
}

/* Detector loop. Pulls frames from the dedicated MD VPSS channel at ~7 Hz,
 * keeps the previous frame as the reference (MD_ALG_MODE_REF — no per-frame
 * copy: two frames are held at once and swapped), runs the IVE SAD+CCL, and
 * debounces the blob result into motion start/stop edges that touch/remove the
 * marker file. Everything is best-effort: on any SDK error the loop skips a tick
 * rather than killing the pipeline. */
static void *md_thread(void *arg)
{
    md_sens_t sens = *(md_sens_t *)arg;
    const MD_CHN mdchn = 0;
    MD_ATTR_S attr;
    IVE_DST_IMAGE_S sad;
    IVE_DST_MEM_INFO_S blob;
    HI_U32 sad_phy = 0, blob_phy = 0;
    HI_VOID *sad_vir = NULL, *blob_vir = NULL;
    VIDEO_FRAME_INFO_S prev, cur;
    int have_prev = 0, motion = 0, on_ticks = 0;
    time_t last_move = 0;
    HI_U32 sad_stride = (W_MD + 15) & ~15u;    /* IVE wants a 16-aligned stride */
    HI_S32 ret;

    /* SETSTOP debounce: start after motion is seen for N consecutive ticks;
     * stop after the scene is quiet for M seconds. Prevents flicker. */
    const int START_TICKS = 2;
    const int STOP_QUIET_S = 3;

    if (HI_IVS_MD_Init() != HI_SUCCESS) {
        SAMPLE_PRT("MD: HI_IVS_MD_Init failed — motion detection off\n");
        return NULL;
    }
    if (HI_MPI_SYS_MmzAlloc(&sad_phy, &sad_vir, "md_sad", NULL,
                            sad_stride * H_MD) != HI_SUCCESS ||
        HI_MPI_SYS_MmzAlloc(&blob_phy, &blob_vir, "md_blob", NULL,
                            sizeof(IVE_CCBLOB_S)) != HI_SUCCESS) {
        SAMPLE_PRT("MD: MmzAlloc failed — motion detection off\n");
        goto out_free;
    }

    memset(&sad, 0, sizeof(sad));
    sad.enType        = IVE_IMAGE_TYPE_U8C1;
    sad.u32PhyAddr[0] = sad_phy;
    sad.pu8VirAddr[0] = (HI_U8 *)sad_vir;
    sad.u16Stride[0]  = (HI_U16)sad_stride;
    sad.u16Width      = W_MD;
    sad.u16Height     = H_MD;

    memset(&blob, 0, sizeof(blob));
    blob.u32PhyAddr  = blob_phy;
    blob.pu8VirAddr  = (HI_U8 *)blob_vir;
    blob.u32Size     = sizeof(IVE_CCBLOB_S);

    memset(&attr, 0, sizeof(attr));
    attr.enAlgMode    = MD_ALG_MODE_REF;
    attr.enSadMode    = IVE_SAD_MODE_MB_4X4;
    attr.enSadOutCtrl = IVE_SAD_OUT_CTRL_THRESH;
    attr.u16Width     = W_MD;
    attr.u16Height    = H_MD;
    attr.u16SadThr    = (HI_U16)sens.sad_thr;
    attr.stCclCtrl.u16InitAreaThr = 4;
    attr.stCclCtrl.u16Step        = 2;
    /* IVE_ADD_CTRL_S fields (x,y of "xA+yB" per hi_ive.h). The SDK's MD_CheckAttr
     * rejects HI_IVS_MD_CreateChn unless u0q16X + u0q16Y == 65536; 32768 + 32768
     * satisfies it. (On hardware: with both 0 CreateChn failed with "must be equal
     * to 65536"; with these it succeeds.) */
    attr.stAddCtrl.u0q16X = 32768;
    attr.stAddCtrl.u0q16Y = 32768;

    if (HI_IVS_MD_CreateChn(mdchn, &attr) != HI_SUCCESS) {
        SAMPLE_PRT("MD: CreateChn failed — motion detection off\n");
        goto out_free;
    }

    SAMPLE_PRT("MD: running (sad_thr=%d min_area=%d)\n", sens.sad_thr, sens.min_area);

    while (!g_stop) {
        IVE_SRC_IMAGE_S stCur, stRef;
        IVE_CCBLOB_S *cc;
        HI_U32 i, area = 0;
        int moved;

        usleep(150 * 1000);        /* ~7 Hz; motion doesn't need every frame */

        if (HI_MPI_VPSS_GetChnFrame(VPSS_GRP, VPSS_CHN_MD, &cur, 200) != HI_SUCCESS)
            continue;
        if (!have_prev) {          /* seed the reference on the first frame */
            prev = cur;
            have_prev = 1;
            continue;
        }

        frame_to_ive_y(&cur,  &stCur);
        frame_to_ive_y(&prev, &stRef);
        ret = HI_IVS_MD_Process(mdchn, &stCur, &stRef, &sad, &blob);

        moved = 0;
        if (ret == HI_SUCCESS) {
            cc = (IVE_CCBLOB_S *)blob_vir;
            for (i = 0; i < cc->u8RegionNum; i++)
                area += cc->astRegion[i].u32Area;
            if (cc->u8RegionNum > 0 && (int)area >= sens.min_area)
                moved = 1;
        }

        /* debounce -> edges */
        if (moved) {
            last_move = time(NULL);
            if (!motion && ++on_ticks >= START_TICKS) {
                FILE *fp = fopen(MOTION_MARKER, "w");
                if (fp) fclose(fp);
                motion = 1;
                SAMPLE_PRT("MD: motion START\n");
            }
        } else {
            on_ticks = 0;
            if (motion && time(NULL) - last_move >= STOP_QUIET_S) {
                remove(MOTION_MARKER);
                motion = 0;
                SAMPLE_PRT("MD: motion STOP\n");
            }
        }

        HI_MPI_VPSS_ReleaseChnFrame(VPSS_GRP, VPSS_CHN_MD, &prev);
        prev = cur;                /* current becomes next tick's reference */
    }

    if (have_prev)
        HI_MPI_VPSS_ReleaseChnFrame(VPSS_GRP, VPSS_CHN_MD, &prev);
    if (motion)
        remove(MOTION_MARKER);
    HI_IVS_MD_DestroyChn(mdchn);
out_free:
    if (sad_vir)  HI_MPI_SYS_MmzFree(sad_phy, sad_vir);
    if (blob_vir) HI_MPI_SYS_MmzFree(blob_phy, blob_vir);
    HI_IVS_MD_Exit();
    return NULL;
}

/* ---- Audio out (speaker) ------------------------------------------------- */
/* Apply a list of "0xADDR=0xVAL" register writes via /dev/mem (speaker-amp enable
 * from the per-model audio_hw.conf table; addresses/values are NOT hardcoded). */
static void reg_write(unsigned long addr, unsigned int val)
{
    unsigned long page = addr & ~0xFFFUL, off = addr & 0xFFF;
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    volatile unsigned char *m;
    if (fd < 0) return;
    m = mmap(0, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, page);
    if (m != MAP_FAILED) {
        *(volatile unsigned int *)(m + off) = val;
        munmap((void *)m, 0x1000);
    }
    close(fd);
}

static void apply_reg_list(const char *list)
{
    char buf[512], *save = NULL, *tok;
    if (!list || !*list) return;
    strncpy(buf, list, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = 0;
    for (tok = strtok_r(buf, " ", &save); tok; tok = strtok_r(NULL, " ", &save)) {
        char *eq = strchr(tok, '=');
        if (!eq) continue;
        *eq = 0;
        reg_write(strtoul(tok, 0, 0), (unsigned int)strtoul(eq + 1, 0, 0));
    }
}

/* CfgAcodec sets only the mic/input path; unmute the DAC output + set its volume
 * (acodec vol_ctrl is inverted: 0x00 loudest .. 0x7F mute). */
static void acodec_dac_output(unsigned int dac_vol)
{
    int fd = open("/dev/acodec", O_RDWR);
    ACODEC_VOL_CTRL v;
    unsigned int unmute = 0;
    if (fd < 0) { SAMPLE_PRT("AO: open /dev/acodec failed\n"); return; }
    v.vol_ctrl = dac_vol; v.vol_ctrl_mute = 0;
    ioctl(fd, ACODEC_SET_DACL_VOL, &v);
    ioctl(fd, ACODEC_SET_DACR_VOL, &v);
    ioctl(fd, ACODEC_SET_DACL_MUTE, &unmute);
    ioctl(fd, ACODEC_SET_DACR_MUTE, &unmute);
    close(fd);
}

/* Bring up inner codec + AO + speaker amp, then play PCM (8kHz/16-bit/mono, signed
 * LE) received on FIFO_AUDIO until g_stop. The amp enable/disable + DAC level come
 * from the per-model table (env); this thread is only started when CAMPIPE_AMP_ON
 * is set. */
static void *ao_thread(void *arg)
{
    AIO_ATTR_S aio;
    AUDIO_FRAME_S frm;
    AUDIO_FADE_S fade;
    HI_U32 phy = 0;
    HI_VOID *vir = NULL;
    HI_U32 bufbytes = AO_PTNUM * 2;
    const char *amp_on  = getenv("CAMPIPE_AMP_ON");
    const char *amp_off = getenv("CAMPIPE_AMP_OFF");
    const char *dacs    = getenv("CAMPIPE_DAC_VOL");
    unsigned int dac_vol = (dacs && *dacs) ? (unsigned int)strtoul(dacs, 0, 0) : 0;
    int fifo_fd = -1;
    int amp = 0;                         /* current speaker-amp state */
    int idle_ticks = 0;
    HI_S32 ret;
    (void)arg;

    memset(&aio, 0, sizeof(aio));
    aio.enSamplerate   = AUDIO_SAMPLE_RATE_8000;
    aio.enBitwidth     = AUDIO_BIT_WIDTH_16;
    aio.enWorkmode     = AIO_MODE_I2S_MASTER;
    aio.enSoundmode    = AUDIO_SOUND_MODE_MONO;
    aio.u32FrmNum      = 30;
    aio.u32PtNumPerFrm = AO_PTNUM;
    aio.u32ChnCnt      = 1;
    aio.u32ClkSel      = 0;

    if ((ret = SAMPLE_COMM_AUDIO_CfgAcodec(&aio)) != HI_SUCCESS) {
        SAMPLE_PRT("AO: CfgAcodec failed %#x — audio out off\n", ret);
        return NULL;
    }
    if ((ret = SAMPLE_COMM_AUDIO_StartAo(AO_DEV, 1, &aio, AUDIO_SAMPLE_RATE_8000,
                                         HI_FALSE, NULL, 0)) != HI_SUCCESS) {
        SAMPLE_PRT("AO: StartAo failed %#x — audio out off\n", ret);
        return NULL;
    }
    HI_MPI_AO_SetVolume(AO_DEV, 0);
    memset(&fade, 0, sizeof(fade));
    HI_MPI_AO_SetMute(AO_DEV, HI_FALSE, &fade);
    acodec_dac_output(dac_vol);
    /* The amp starts OFF: powering it while idle hisses (confirmed on hardware -
     * PTT playback leaves audible hiss unless the amp is switched off again once
     * playback ends). It is switched on only while audio is actually flowing and
     * off again once it stops - see the debounced gate in the loop below. */

    if (HI_MPI_SYS_MmzAlloc(&phy, &vir, "ao_play", NULL, bufbytes) != HI_SUCCESS) {
        SAMPLE_PRT("AO: MmzAlloc failed — audio out off\n");
        goto out_ao;
    }
    memset(&frm, 0, sizeof(frm));
    frm.enBitwidth    = AUDIO_BIT_WIDTH_16;
    frm.enSoundmode   = AUDIO_SOUND_MODE_MONO;
    frm.pVirAddr[0]   = vir;
    frm.u32PhyAddr[0] = phy;
    frm.u32Len        = AO_PTNUM;

    unlink(FIFO_AUDIO);
    if (mkfifo(FIFO_AUDIO, 0666) < 0 && errno != EEXIST)
        SAMPLE_PRT("AO: mkfifo %s failed: %s\n", FIFO_AUDIO, strerror(errno));

    /* Open O_RDWR|O_NONBLOCK: we also hold a writer end, so the read side never
     * blocks and never sees EOF - poll() returns POLLIN only when a real writer has
     * queued PCM. This keeps the loop interruptible (g_stop is re-checked every poll
     * timeout); a blocking O_RDONLY open would stall pthread_join at teardown and
     * leave campipe un-killable. */
    fifo_fd = open(FIFO_AUDIO, O_RDWR | O_NONBLOCK);
    if (fifo_fd < 0) {
        SAMPLE_PRT("AO: open %s failed: %s\n", FIFO_AUDIO, strerror(errno));
        HI_MPI_SYS_MmzFree(phy, vir);
        goto out_ao;
    }

    SAMPLE_PRT("AO: speaker up (8kHz/16/mono, dac=0x%x); playing from %s\n",
               dac_vol, FIFO_AUDIO);

    /* Play PCM frames as they arrive on the FIFO. poll (not a blocking read) keeps
     * this interruptible - g_stop is re-checked every timeout - so teardown never
     * hangs in pthread_join.
     *
     * Amp gate (PTT squelch, radio-style): power the amp the instant real data
     * shows up, and cut it again only after the scene has been quiet for several
     * consecutive ticks - both no new FIFO data AND the AO hardware queue drained
     * (u32ChnBusyNum == 0). Requiring BOTH, sustained across IDLE_TICKS polls, is
     * what avoids cutting mid-playback: a single quiet poll doesn't prove the AO
     * buffer actually finished draining (the FIFO can empty into it in one burst
     * while HW playback is still catching up), so one bad reading just resets the
     * debounce instead of flipping the amp off under running audio. */
    const int IDLE_TICKS = 3;            /* ~3 * 200ms poll = 600ms hang time */
    while (!g_stop) {
        struct pollfd pfd = { fifo_fd, POLLIN, 0 };
        ssize_t n;
        int got_data = 0;

        if (poll(&pfd, 1, 200) > 0 && (pfd.revents & POLLIN)) {
            n = read(fifo_fd, vir, bufbytes);
            if (n > 0) {
                got_data = 1;
                if (!amp) { apply_reg_list(amp_on); amp = 1; }
                if ((size_t)n < bufbytes)
                    memset((char *)vir + n, 0, bufbytes - n);
                HI_MPI_AO_SendFrame(AO_DEV, AO_CHN, &frm, 1000);
            }
        }

        if (got_data) {
            idle_ticks = 0;
        } else if (amp) {
            AO_CHN_STATE_S st;
            if (HI_MPI_AO_QueryChnStat(AO_DEV, AO_CHN, &st) == HI_SUCCESS &&
                st.u32ChnBusyNum == 0) {
                if (++idle_ticks >= IDLE_TICKS) {
                    apply_reg_list(amp_off);
                    amp = 0;
                    idle_ticks = 0;
                }
            } else {
                idle_ticks = 0;   /* still draining - reset the debounce */
            }
        }
    }

    close(fifo_fd);
    HI_MPI_SYS_MmzFree(phy, vir);
out_ao:
    if (amp) apply_reg_list(amp_off);    /* disable speaker amp if still on */
    SAMPLE_COMM_AUDIO_StopAo(AO_DEV, 1, HI_FALSE, HI_FALSE);
    HI_MPI_AO_Disable(AO_DEV);
    return NULL;
}

int main(void)
{
    VB_CONF_S vb;
    SAMPLE_VI_CONFIG_S vi;
    VPSS_GRP_ATTR_S grp;
    VPSS_CHN_ATTR_S chn_attr;
    VPSS_CHN_MODE_S chn_mode;
    SIZE_S sensor_sz;
    PIC_SIZE_E sensor_pic;
    HI_S32 ret;
    pthread_t th_high, th_low, th_md, th_ao;
    stream_ctx_t ctx_high = { CHN_HIGH, FIFO_HIGH, 512 * 1024 };
    stream_ctx_t ctx_low  = { CHN_LOW,  FIFO_LOW,  128 * 1024 };
    struct { VPSS_CHN chn; HI_U32 w, h; COMPRESS_MODE_E cmp; } vchn[] = {
        { CHN_HIGH,      W_HIGH, H_HIGH, COMPRESS_MODE_SEG  },
        { CHN_LOW,       W_LOW,  H_LOW,  COMPRESS_MODE_SEG  },
        { VPSS_CHN_SNAP, W_SNAP, H_SNAP, COMPRESS_MODE_NONE },
    };
    int i;

    /* Motion detection is opt-in via CAMPIPE_MD (set by native_pipeline.sh from
     * config.MOTION_DETECTION). When off, the MD VPSS channel / IVE buffers /
     * detector thread are never created — zero extra MMZ, matters in offline. */
    const char *md_env  = getenv("CAMPIPE_MD");
    int md_on = md_env && (!strcmp(md_env, "on") || !strcmp(md_env, "yes") ||
                           !strcmp(md_env, "1"));
    md_sens_t md_sens = md_sens_for(getenv("CAMPIPE_MD_SENS"));

    /* Audio out (speaker) is opt-in: native_pipeline.sh sets CAMPIPE_AMP_ON from the
     * per-model audio_hw.conf table only when the model is mapped and audio-out is
     * enabled. No amp mapping -> no AO thread (speaker untouched). */
    const char *ao_env = getenv("CAMPIPE_AMP_ON");
    int ao_on = ao_env && *ao_env;

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, SIG_IGN);

    SAMPLE_PRT("cfg: VBLK=%s H264HI_KB=%s H264LO_KB=%s JPEGHI_KB=%s JPEGLO_KB=%s LDC=%s MD=%s(%s)\n",
               getenv("CAMPIPE_VBLK") ?: "def", getenv("CAMPIPE_H264HI_KB") ?: "def",
               getenv("CAMPIPE_H264LO_KB") ?: "def", getenv("CAMPIPE_JPEGHI_KB") ?: "def",
               getenv("CAMPIPE_JPEGLO_KB") ?: "def", getenv("CAMPIPE_LDC") ?: "0",
               md_on ? "on" : "off", getenv("CAMPIPE_MD_SENS") ?: "low");

    if (md_on)
        mkdir(IPC_DIR, 0755);      /* event-bus dir; onvif_notify_server needs it */

    /* Sensor native size: F22 = 1080p, so VPSS chn0 is a passthrough. */
    sensor_pic = PIC_HD1080;
    SAMPLE_COMM_SYS_GetPicSize(g_norm, sensor_pic, &sensor_sz);

    /* --- VB pools: one per distinct frame size we route through VPSS --- */
    memset(&vb, 0, sizeof(vb));
    vb.u32MaxPoolCnt = 128;
    vb.astCommPool[0].u32BlkSize =
        SAMPLE_COMM_SYS_CalcPicVbBlkSize(g_norm, sensor_pic,
                                         SAMPLE_PIXEL_FORMAT, SAMPLE_SYS_ALIGN_WIDTH);
    /* pool0 depth (1080p capture blocks). Offline VI writes each frame to a
     * pool0 block that VPSS must return; the VI->DDR->VPSS round-trip (plus the
     * LDC pass) needs depth or VI starves (VbFail). Measured on hardware: 5 is
     * the floor for smooth offline+LDC (4 -> ~9fps, 5 -> ~14fps); online needs
     * only ~3 (no DDR frame path). Default 5 (offline-safe); the boot script
     * sets CAMPIPE_VBLK per PIPELINE mode (online=3, offline=5). */
    vb.astCommPool[0].u32BlkCnt = (HI_U32)(getenv("CAMPIPE_VBLK") && *getenv("CAMPIPE_VBLK")
                                           ? atoi(getenv("CAMPIPE_VBLK")) : 5);
    if (vb.astCommPool[0].u32BlkCnt < 1) vb.astCommPool[0].u32BlkCnt = 1;
    vb.astCommPool[1].u32BlkSize = W_LOW * H_LOW * 2;
    vb.astCommPool[1].u32BlkCnt = 4;
    vb.astCommPool[2].u32BlkSize = W_SNAP * H_SNAP * 2;
    /* chn2 (snap JPEG) and the MD chn3 are the same 320x192 size, so both draw
     * from this pool. MD holds two frames at once (cur+ref) plus user-get depth,
     * so give it extra blocks when enabled. */
    vb.astCommPool[2].u32BlkCnt = md_on ? 8 : 4;

    if ((ret = SAMPLE_COMM_SYS_Init(&vb)) != HI_SUCCESS) {
        SAMPLE_PRT("SYS_Init failed %#x\n", ret);
        return 1;
    }

    /* --- VI + ISP (F22 via the stock sensor plugin, own start sequence) --- */
    memset(&vi, 0, sizeof(vi));
    vi.enViMode   = SENSOR_TYPE;   /* still drives MIPI/CMOS attr + VPSS bind */
    vi.enRotate   = ROTATE_NONE;
    vi.enNorm     = VIDEO_ENCODING_MODE_AUTO;
    vi.enViChnSet = VI_CHN_SET_NORMAL;
    vi.enWDRMode  = WDR_MODE_NONE;
    if ((ret = f22_start_vi_isp(&vi)) != HI_SUCCESS) {
        SAMPLE_PRT("StartVi failed %#x\n", ret);
        goto err_sys;
    }

    /* --- VPSS group fed by VI, then the three scaler channels --- */
    memset(&grp, 0, sizeof(grp));
    grp.u32MaxW = sensor_sz.u32Width;
    grp.u32MaxH = sensor_sz.u32Height;
    grp.bNrEn   = HI_TRUE;
    grp.enPixFmt = PIXEL_FORMAT_YUV_SEMIPLANAR_420;
    grp.enDieMode = VPSS_DIE_MODE_NODIE;
    if ((ret = SAMPLE_COMM_VPSS_StartGroup(VPSS_GRP, &grp)) != HI_SUCCESS) {
        SAMPLE_PRT("VPSS StartGroup failed %#x\n", ret);
        goto err_vi;
    }
    if ((ret = SAMPLE_COMM_VI_BindVpss(vi.enViMode)) != HI_SUCCESS) {
        SAMPLE_PRT("VI BindVpss failed %#x\n", ret);
        goto err_vpss;
    }
    for (i = 0; i < 3; i++) {
        memset(&chn_mode, 0, sizeof(chn_mode));
        chn_mode.enChnMode      = VPSS_CHN_MODE_USER;
        chn_mode.bDouble        = HI_FALSE;
        chn_mode.enPixelFormat  = PIXEL_FORMAT_YUV_SEMIPLANAR_420;
        chn_mode.u32Width       = vchn[i].w;
        chn_mode.u32Height      = vchn[i].h;
        chn_mode.enCompressMode = vchn[i].cmp;
        memset(&chn_attr, 0, sizeof(chn_attr));
        chn_attr.s32SrcFrameRate = -1;
        chn_attr.s32DstFrameRate = -1;
        ret = SAMPLE_COMM_VPSS_EnableChn(VPSS_GRP, vchn[i].chn,
                                         &chn_attr, &chn_mode, HI_NULL);
        if (ret != HI_SUCCESS) {
            SAMPLE_PRT("VPSS EnableChn %d failed %#x\n", vchn[i].chn, ret);
            goto err_vpss;
        }
    }

    /* --- MD channel: a 4th, downscaled VPSS chn read in user mode by the IVE
     * detector (NOT bound to a VENC). Needs a non-zero user-get depth so
     * GetChnFrame delivers frames. Only created when motion detection is on. */
    if (md_on) {
        memset(&chn_mode, 0, sizeof(chn_mode));
        chn_mode.enChnMode      = VPSS_CHN_MODE_USER;
        chn_mode.bDouble        = HI_FALSE;
        chn_mode.enPixelFormat  = PIXEL_FORMAT_YUV_SEMIPLANAR_420;
        chn_mode.u32Width       = W_MD;
        chn_mode.u32Height      = H_MD;
        chn_mode.enCompressMode = COMPRESS_MODE_NONE;
        memset(&chn_attr, 0, sizeof(chn_attr));
        chn_attr.s32SrcFrameRate = -1;
        chn_attr.s32DstFrameRate = -1;
        ret = SAMPLE_COMM_VPSS_EnableChn(VPSS_GRP, VPSS_CHN_MD,
                                         &chn_attr, &chn_mode, HI_NULL);
        if (ret != HI_SUCCESS) {
            SAMPLE_PRT("VPSS EnableChn %d (MD) failed %#x — motion detection off\n",
                       VPSS_CHN_MD, ret);
            md_on = 0;
        } else {
            HI_MPI_VPSS_SetDepth(VPSS_GRP, VPSS_CHN_MD, 3);
        }
    }

    /* --- VENC: two H.264 streams + two idle JPEG snap channels --- */
    if (start_h264(CHN_HIGH, CHN_HIGH, W_HIGH, H_HIGH, 2048, SNS_FPS) != HI_SUCCESS)
        goto err_vpss;
    if (start_h264(CHN_LOW, CHN_LOW, W_LOW, H_LOW, 512, SNS_FPS) != HI_SUCCESS)
        goto err_vpss;
    if (start_jpeg(VENC_JPEG_HIGH, CHN_HIGH, W_HIGH, H_HIGH) != HI_SUCCESS)
        goto err_vpss;
    if (start_jpeg(VENC_JPEG_LOW, VPSS_CHN_SNAP, W_SNAP, H_SNAP) != HI_SUCCESS)
        goto err_vpss;

    pthread_create(&th_high, NULL, stream_thread, &ctx_high);
    pthread_create(&th_low, NULL, stream_thread, &ctx_low);
    if (md_on)
        pthread_create(&th_md, NULL, md_thread, &md_sens);
    if (ao_on)
        pthread_create(&th_ao, NULL, ao_thread, NULL);

    SAMPLE_PRT("campipe: native pipeline running (high+low H.264, JPEG snap idle%s%s)\n",
               md_on ? ", motion detection on" : "", ao_on ? ", audio out on" : "");

    while (!g_stop)
        pause();

    pthread_join(th_high, NULL);
    pthread_join(th_low, NULL);
    if (md_on)
        pthread_join(th_md, NULL);
    if (ao_on)
        pthread_join(th_ao, NULL);

    /* Best-effort teardown; on a clean stop the startup script also re-inits. */
    HI_MPI_VENC_StopRecvPic(CHN_HIGH);
    HI_MPI_VENC_StopRecvPic(CHN_LOW);
err_vpss:
    SAMPLE_COMM_VPSS_Stop(1, md_on ? 4 : 3);
err_vi:
    SAMPLE_COMM_VI_StopVi(&vi);
err_sys:
    SAMPLE_COMM_SYS_Exit();
    return g_stop ? 0 : 1;
}
