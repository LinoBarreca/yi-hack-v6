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
#include <sys/stat.h>
#include <sys/select.h>

#include "sample_comm.h"

/* ---- pipeline geometry (matches the stock y20 layout) ------------------- */
#define VPSS_GRP        0
#define CHN_HIGH        0          /* VENC chn + VPSS chn for the 1080p H.264 */
#define CHN_LOW         1          /* VENC chn + VPSS chn for the 640x360 H.264 */
#define VPSS_CHN_SNAP   2          /* 320x192 VPSS chn feeding the small JPEG  */
#define VENC_JPEG_HIGH  2          /* on-demand JPEG, fed by VPSS chn0 (1080p) */
#define VENC_JPEG_LOW   3          /* on-demand JPEG, fed by VPSS chn2 (320x192)*/

#define W_HIGH 1920
#define H_HIGH 1080
#define W_LOW  640
#define H_LOW  360
#define W_SNAP 320
#define H_SNAP 192

#define FIFO_HIGH "/tmp/h264_high_fifo"
#define FIFO_LOW  "/tmp/h264_low_fifo"

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
    pthread_t th_high, th_low;
    stream_ctx_t ctx_high = { CHN_HIGH, FIFO_HIGH, 512 * 1024 };
    stream_ctx_t ctx_low  = { CHN_LOW,  FIFO_LOW,  128 * 1024 };
    struct { VPSS_CHN chn; HI_U32 w, h; COMPRESS_MODE_E cmp; } vchn[] = {
        { CHN_HIGH,      W_HIGH, H_HIGH, COMPRESS_MODE_SEG  },
        { CHN_LOW,       W_LOW,  H_LOW,  COMPRESS_MODE_SEG  },
        { VPSS_CHN_SNAP, W_SNAP, H_SNAP, COMPRESS_MODE_NONE },
    };
    int i;

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, SIG_IGN);

    SAMPLE_PRT("cfg: VBLK=%s H264HI_KB=%s H264LO_KB=%s JPEGHI_KB=%s JPEGLO_KB=%s LDC=%s\n",
               getenv("CAMPIPE_VBLK") ?: "def", getenv("CAMPIPE_H264HI_KB") ?: "def",
               getenv("CAMPIPE_H264LO_KB") ?: "def", getenv("CAMPIPE_JPEGHI_KB") ?: "def",
               getenv("CAMPIPE_JPEGLO_KB") ?: "def", getenv("CAMPIPE_LDC") ?: "0");

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
    vb.astCommPool[2].u32BlkCnt = 4;

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

    SAMPLE_PRT("campipe: native pipeline running (high+low H.264, JPEG snap idle)\n");

    while (!g_stop)
        pause();

    pthread_join(th_high, NULL);
    pthread_join(th_low, NULL);

    /* Best-effort teardown; on a clean stop the startup script also re-inits. */
    HI_MPI_VENC_StopRecvPic(CHN_HIGH);
    HI_MPI_VENC_StopRecvPic(CHN_LOW);
err_vpss:
    SAMPLE_COMM_VPSS_Stop(1, 3);
err_vi:
    SAMPLE_COMM_VI_StopVi(&vi);
err_sys:
    SAMPLE_COMM_SYS_Exit();
    return g_stop ? 0 : 1;
}
