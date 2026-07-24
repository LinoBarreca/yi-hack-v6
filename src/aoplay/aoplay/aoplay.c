/*
 * aoplay - HiSilicon AO (audio-out / speaker) bring-up & validation tool.
 *
 * Used to bring up and validate the speaker path on a camera model - especially a
 * NEW one being added to the audio_hw.conf table. It configures the inner codec +
 * AO (via the SDK helpers SAMPLE_COMM_AUDIO_CfgAcodec / StartAo), unmutes the DAC,
 * enables the speaker amplifier, and plays a raw PCM file (8 kHz/16-bit/mono, signed
 * LE) or a synthesized 1 kHz tone.
 *
 * The amp enable and DAC level are BOARD-SPECIFIC and NOT hardcoded: they come from
 * the per-model audio_hw.conf table, passed in as env - CAMPIPE_AMP_ON (a list of
 * "0xADDR=0xVAL" register writes) and CAMPIPE_DAC_VOL (acodec vol_ctrl, 0x00 loud ..
 * 0x7F mute) - the same values campipe uses in production. Args override for manual
 * sweeping while mapping a new board.
 *
 * The production audio path is AO inside campipe (src/campipe); this standalone tool
 * exists only for isolated bring-up. Requires the SDK audio modules (acodec,
 * hi3518e_ao/aio) loaded and no other process holding the MPP system (campipe stopped).
 *
 * usage: aoplay [dac_vol_hex] [ao_vol_db] [pcm_file]   (env: CAMPIPE_AMP_ON/DAC_VOL)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <math.h>

#include "sample_comm.h"
#include "acodec.h"

/* Apply a list of "0xADDR=0xVAL" register writes via /dev/mem (used to enable the
 * board's speaker amplifier - the addresses/values come from the per-model
 * audio_hw.conf table, NOT hardcoded, since they differ across camera models). */
static void reg_write(unsigned long addr, unsigned int val)
{
    unsigned long page = addr & ~0xFFFUL, off = addr & 0xFFF;
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    volatile unsigned char *m;
    if (fd < 0) { SAMPLE_PRT("aoplay: open /dev/mem failed\n"); return; }
    m = mmap(0, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, page);
    if (m != MAP_FAILED) {
        *(volatile unsigned int *)(m + off) = val;
        munmap((void *)m, 0x1000);
        SAMPLE_PRT("aoplay: reg 0x%08lX = 0x%08X\n", addr, val);
    } else {
        SAMPLE_PRT("aoplay: mmap 0x%08lX failed\n", page);
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

#define AO_DEV          0
#define AO_CHN          0
#define SR              8000     /* 8 kHz sample rate                         */
#define PTNUM           320      /* points per frame (40 ms @ 8 kHz)          */
#define TONE_HZ         1000     /* synthesized test tone                     */
#define TONE_SECONDS    3
#define TONE_AMPLITUDE  8000     /* < 32767, comfortable level                */

/* The SDK inner-codec config only sets up the mic/input path; the DAC (speaker)
 * output is left at hardware default. Unmute the DAC and set its volume here.
 * ACODEC_VOL_CTRL.vol_ctrl is INVERTED: 0x00 = loudest .. 0x7e .. 0x7F = mute.
 * The value comes from the model's audio_hw.conf DAC_VOL (via env), or an arg when
 * sweeping to characterise a new board. */
static void acodec_enable_output(unsigned int dac_vol)
{
    int fd = open("/dev/acodec", O_RDWR);
    ACODEC_VOL_CTRL v;
    unsigned int unmute = 0;
    if (fd < 0) { SAMPLE_PRT("aoplay: open /dev/acodec failed\n"); return; }
    v.vol_ctrl = dac_vol;
    v.vol_ctrl_mute = 0;
    if (ioctl(fd, ACODEC_SET_DACL_VOL, &v))  SAMPLE_PRT("aoplay: DACL_VOL ioctl failed\n");
    if (ioctl(fd, ACODEC_SET_DACR_VOL, &v))  SAMPLE_PRT("aoplay: DACR_VOL ioctl failed\n");
    if (ioctl(fd, ACODEC_SET_DACL_MUTE, &unmute)) SAMPLE_PRT("aoplay: DACL_MUTE ioctl failed\n");
    if (ioctl(fd, ACODEC_SET_DACR_MUTE, &unmute)) SAMPLE_PRT("aoplay: DACR_MUTE ioctl failed\n");
    close(fd);
    SAMPLE_PRT("aoplay: acodec DAC unmuted, vol_ctrl=0x%02x\n", dac_vol);
}

int main(int argc, char **argv)
{
    VB_CONF_S vb;
    AIO_ATTR_S aio;
    AUDIO_FRAME_S frm;
    HI_U32 phy = 0;
    HI_VOID *vir = NULL;
    HI_U32 bufbytes = PTNUM * 2;         /* 16-bit mono */
    HI_S32 ret;
    FILE *fp = NULL;
    unsigned int dac_vol = 0x00;         /* acodec DAC vol_ctrl (0x00 loud..0x7F mute) */
    int ao_vol_db = 0;                    /* HI_MPI_AO_SetVolume dB              */
    AUDIO_FADE_S fade;
    /* Amp enable + DAC level come from the per-model audio_hw.conf table via env
     * (set by native_pipeline.sh); args are for manual override/sweeping in test. */
    const char *env_amp = getenv("CAMPIPE_AMP_ON");
    const char *env_dac = getenv("CAMPIPE_DAC_VOL");

    /* usage: aoplay [dac_vol_hex] [ao_vol_db] [pcm_file] ; env overrides dac */
    if (env_dac && *env_dac) dac_vol = (unsigned int)strtol(env_dac, NULL, 0);
    if (argc > 1) dac_vol   = (unsigned int)strtol(argv[1], NULL, 0);
    if (argc > 2) ao_vol_db = (int)strtol(argv[2], NULL, 0);
    if (argc > 3) {
        fp = fopen(argv[3], "rb");
        if (!fp) { SAMPLE_PRT("aoplay: cannot open %s\n", argv[3]); return 1; }
    }

    /* Minimal MPP system: AO needs the MMZ allocator up. Tiny VB pool. */
    memset(&vb, 0, sizeof(vb));
    vb.u32MaxPoolCnt = 1;
    vb.astCommPool[0].u32BlkSize = 4096;
    vb.astCommPool[0].u32BlkCnt  = 4;
    if ((ret = SAMPLE_COMM_SYS_Init(&vb)) != HI_SUCCESS) {
        SAMPLE_PRT("aoplay: SYS_Init failed %#x\n", ret);
        if (fp) fclose(fp);
        return 1;
    }

    /* AO attributes: 8 kHz / 16-bit / mono, inner codec, I2S master. */
    memset(&aio, 0, sizeof(aio));
    aio.enSamplerate   = AUDIO_SAMPLE_RATE_8000;
    aio.enBitwidth     = AUDIO_BIT_WIDTH_16;
    aio.enWorkmode     = AIO_MODE_I2S_MASTER;
    aio.enSoundmode    = AUDIO_SOUND_MODE_MONO;
    aio.u32EXFlag      = 0;
    aio.u32FrmNum      = 30;
    aio.u32PtNumPerFrm = PTNUM;
    aio.u32ChnCnt      = 1;
    aio.u32ClkSel      = 0;

    if ((ret = SAMPLE_COMM_AUDIO_CfgAcodec(&aio)) != HI_SUCCESS) {
        SAMPLE_PRT("aoplay: CfgAcodec failed %#x\n", ret);
        goto err_sys;
    }
    /* no resample (input == AO rate), no VQE */
    if ((ret = SAMPLE_COMM_AUDIO_StartAo(AO_DEV, 1, &aio, AUDIO_SAMPLE_RATE_8000,
                                         HI_FALSE, NULL, 0)) != HI_SUCCESS) {
        SAMPLE_PRT("aoplay: StartAo failed %#x\n", ret);
        goto err_sys;
    }

    /* Unmute + set volume at BOTH levels - StartAo/CfgAcodec set neither, so the
     * speaker is silent by default: AO (digital path) and the acodec DAC (analog). */
    HI_MPI_AO_SetVolume(AO_DEV, ao_vol_db);
    memset(&fade, 0, sizeof(fade));      /* bFade = HI_FALSE: no fade */
    HI_MPI_AO_SetMute(AO_DEV, HI_FALSE, &fade);
    acodec_enable_output(dac_vol);
    apply_reg_list(env_amp);             /* enable the speaker amp (per-model, from table) */

    /* One-frame MMZ buffer the AO hardware reads by physical address. */
    if (HI_MPI_SYS_MmzAlloc(&phy, &vir, "aoplay", NULL, bufbytes) != HI_SUCCESS) {
        SAMPLE_PRT("aoplay: MmzAlloc failed\n");
        goto err_ao;
    }

    memset(&frm, 0, sizeof(frm));
    frm.enBitwidth    = AUDIO_BIT_WIDTH_16;
    frm.enSoundmode   = AUDIO_SOUND_MODE_MONO;
    frm.pVirAddr[0]   = vir;
    frm.u32PhyAddr[0] = phy;
    frm.u32Len        = PTNUM;           /* samples per channel */

    SAMPLE_PRT("aoplay: AO up (8kHz/16/mono, ao_vol=%ddB); playing %s\n",
               ao_vol_db, fp ? argv[3] : "a 1kHz tone");

    if (fp) {
        size_t n;
        while ((n = fread(vir, 1, bufbytes, fp)) > 0) {
            if (n < bufbytes)
                memset((char *)vir + n, 0, bufbytes - n);
            if ((ret = HI_MPI_AO_SendFrame(AO_DEV, AO_CHN, &frm, 1000)) != HI_SUCCESS) {
                SAMPLE_PRT("aoplay: SendFrame failed %#x\n", ret);
                break;
            }
        }
    } else {
        int total = TONE_SECONDS * SR / PTNUM;
        int i, k;
        double ph = 0.0, dph = 2.0 * M_PI * TONE_HZ / SR;
        short *s = (short *)vir;
        for (i = 0; i < total; i++) {
            for (k = 0; k < PTNUM; k++) {
                s[k] = (short)(TONE_AMPLITUDE * sin(ph));
                ph += dph;
                if (ph > 2.0 * M_PI) ph -= 2.0 * M_PI;
            }
            if ((ret = HI_MPI_AO_SendFrame(AO_DEV, AO_CHN, &frm, 1000)) != HI_SUCCESS) {
                SAMPLE_PRT("aoplay: SendFrame failed %#x\n", ret);
                break;
            }
        }
    }

    usleep(500 * 1000);                  /* let the AO buffer drain */
    SAMPLE_PRT("aoplay: done\n");

    HI_MPI_SYS_MmzFree(phy, vir);
err_ao:
    SAMPLE_COMM_AUDIO_StopAo(AO_DEV, 1, HI_FALSE, HI_FALSE);
    HI_MPI_AO_Disable(AO_DEV);
err_sys:
    if (fp) fclose(fp);
    SAMPLE_COMM_SYS_Exit();
    return 0;
}
