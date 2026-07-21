/*
 * Copyright (c) 2026 Lino Barreca
 * https://github.com/LinoBarreca/yi-hack-v6
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * hwsnap - grab one JPEG from a hardware VENC snap channel.
 *
 * The stock Yi media daemon (rmm) configures the full MPP pipeline at boot,
 * including two on-demand JPEG channels (Start=0 in /proc/umap/venc):
 *   chn 2: 1920x1080 JPEG   chn 3: 320x192 JPEG   (fed by the live VPSS group)
 * This tool attaches to that live pipeline from a separate process - no MPP
 * init of our own (yet), rmm keeps ownership - requests a single picture and writes
 * the hardware-encoded JPEG out. Replaces a ~22s software decode/re-encode
 * (imggrabber) with a hardware-encoded JPEG produced in a few milliseconds.
 *
 * The snap channel is SHARED with rmm (cloud/app snapshots use it too): a
 * concurrent request can steal our frame or deliver ours to rmm. Rare and
 * harmless for stills - the caller just retries. Every exit path calls
 * HI_MPI_VENC_StopRecvPic so the channel is always left idle as rmm expects.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <signal.h>
#include <sys/select.h>
#include <sys/time.h>

#include "hi_comm_venc.h"
#include "mpi_venc.h"

static long long now_ms(void)
{
    struct timeval te;
    gettimeofday(&te, NULL);
    return te.tv_sec * 1000LL + te.tv_usec / 1000;
}

static void print_usage(char *progname)
{
    fprintf(stderr, "\nUsage: %s [-c CHN] [-o FILE] [-t TIMEOUT_MS] [-d]\n\n", progname);
    fprintf(stderr, "\t-c CHN, --chn CHN\n");
    fprintf(stderr, "\t\tVENC snap channel (default 2 = high res; 3 = low res)\n");
    fprintf(stderr, "\t-o FILE, --output FILE\n");
    fprintf(stderr, "\t\toutput file (default stdout)\n");
    fprintf(stderr, "\t-t TIMEOUT_MS, --timeout TIMEOUT_MS\n");
    fprintf(stderr, "\t\tmax wait for the encoded picture (default 3000)\n");
    fprintf(stderr, "\t-d, --debug\n");
    fprintf(stderr, "\t\tprint timing/debug info to stderr\n");
}

int main(int argc, char **argv)
{
    VENC_CHN chn = 2;
    const char *out_file = NULL;
    int timeout_ms = 3000;
    int debug = 0;

    VENC_RECV_PIC_PARAM_S recv_param;
    VENC_CHN_STAT_S stat;
    VENC_STREAM_S stream;
    struct timeval tv;
    fd_set read_fds;
    FILE *fout = stdout;
    HI_S32 fd, ret;
    HI_U32 i;
    long long t0, t1;
    int exit_code = 1;
    int started = 0;
    unsigned char *jpeg_buf = NULL;
    HI_U32 jpeg_len = 0, packs = 0;

    // A cancelled request in the live viewer closes our stdout pipe; without this a
    // write below would raise SIGPIPE and kill us before ReleaseStream, leaking the
    // VENC buffer (see the release-before-write note further down). Ignore it so the
    // write just fails and we still clean up.
    signal(SIGPIPE, SIG_IGN);

    while (1) {
        static struct option long_options[] = {
            {"chn",     required_argument, 0, 'c'},
            {"output",  required_argument, 0, 'o'},
            {"timeout", required_argument, 0, 't'},
            {"debug",   no_argument,       0, 'd'},
            {"help",    no_argument,       0, 'h'},
            {0, 0, 0, 0}
        };
        int c = getopt_long(argc, argv, "c:o:t:dh", long_options, NULL);
        if (c == -1) break;

        switch (c) {
        case 'c': chn = atoi(optarg); break;
        case 'o': out_file = optarg; break;
        case 't': timeout_ms = atoi(optarg); break;
        case 'd': debug = 1; break;
        case 'h':
        default:
            print_usage(argv[0]);
            return 1;
        }
    }

    // Same disable switch imggrabber honors: keeps both capture backends
    // consistent regardless of which one a caller invokes directly.
    if (access("/tmp/snapshot.disabled", F_OK) == 0) {
        fprintf(stderr, "Snapshot is disabled\n");
        return 0;
    }

    t0 = now_ms();

    // Ask the live pipeline for exactly one picture on the snap channel.
    memset(&recv_param, 0, sizeof(recv_param));
    recv_param.s32RecvPicNum = 1;
    ret = HI_MPI_VENC_StartRecvPicEx(chn, &recv_param);
    if (ret != HI_SUCCESS) {
        fprintf(stderr, "HI_MPI_VENC_StartRecvPicEx(%d) failed: %#x\n", chn, ret);
        return 1;
    }
    started = 1;

    fd = HI_MPI_VENC_GetFd(chn);
    if (fd < 0) {
        fprintf(stderr, "HI_MPI_VENC_GetFd(%d) failed: %#x\n", chn, fd);
        goto out_stop;
    }

    FD_ZERO(&read_fds);
    FD_SET(fd, &read_fds);
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    ret = select(fd + 1, &read_fds, NULL, NULL, &tv);
    if (ret < 0) {
        fprintf(stderr, "select failed\n");
        goto out_stop;
    }
    if (ret == 0) {
        fprintf(stderr, "timed out after %d ms (concurrent snapshot? retry)\n", timeout_ms);
        goto out_stop;
    }

    ret = HI_MPI_VENC_Query(chn, &stat);
    if (ret != HI_SUCCESS) {
        fprintf(stderr, "HI_MPI_VENC_Query(%d) failed: %#x\n", chn, ret);
        goto out_stop;
    }
    if (stat.u32CurPacks == 0) {
        fprintf(stderr, "no packs available (frame stolen by a concurrent snapshot? retry)\n");
        goto out_stop;
    }

    memset(&stream, 0, sizeof(stream));
    stream.pstPack = malloc(sizeof(VENC_PACK_S) * stat.u32CurPacks);
    if (stream.pstPack == NULL) {
        fprintf(stderr, "malloc failed\n");
        goto out_stop;
    }
    stream.u32PackCount = stat.u32CurPacks;
    ret = HI_MPI_VENC_GetStream(chn, &stream, timeout_ms);
    if (ret != HI_SUCCESS) {
        fprintf(stderr, "HI_MPI_VENC_GetStream(%d) failed: %#x\n", chn, ret);
        free(stream.pstPack);
        goto out_stop;
    }

    // Copy the encoded bytes into our own buffer and RELEASE the VENC stream BEFORE
    // writing anything to the output. Writing to stdout can block or hit a broken
    // pipe (a cancelled HTTP request in the live viewer), and if that killed us
    // between GetStream and ReleaseStream the VENC buffer would leak.
    packs = stream.u32PackCount;
    jpeg_len = 0;
    for (i = 0; i < stream.u32PackCount; i++)
        jpeg_len += stream.pstPack[i].u32Len - stream.pstPack[i].u32Offset;
    jpeg_buf = malloc(jpeg_len);
    if (jpeg_buf != NULL) {
        HI_U32 off = 0;
        for (i = 0; i < stream.u32PackCount; i++) {
            VENC_PACK_S *pack = &stream.pstPack[i];
            HI_U32 len = pack->u32Len - pack->u32Offset;
            memcpy(jpeg_buf + off, pack->pu8Addr + pack->u32Offset, len);
            off += len;
        }
    }

    ret = HI_MPI_VENC_ReleaseStream(chn, &stream);
    if (ret != HI_SUCCESS)
        fprintf(stderr, "HI_MPI_VENC_ReleaseStream(%d) failed: %#x\n", chn, ret);
    free(stream.pstPack);

    if (jpeg_buf == NULL) {
        fprintf(stderr, "malloc failed\n");
        goto out_stop;
    }

    // From here the VENC buffer is already back with the encoder, so a SIGPIPE or a
    // short write below can no longer leak it or wedge the channel.
    if (out_file != NULL) {
        fout = fopen(out_file, "w");
        if (fout == NULL) {
            fprintf(stderr, "cannot open %s\n", out_file);
            free(jpeg_buf);
            goto out_stop;
        }
    }

    fwrite(jpeg_buf, 1, jpeg_len, fout);
    fflush(fout);
    if (out_file != NULL)
        fclose(fout);
    free(jpeg_buf);

    t1 = now_ms();
    if (debug)
        fprintf(stderr, "JPEG captured from chn %d in %lld ms (%u packs)\n",
                chn, t1 - t0, packs);
    exit_code = 0;

out_stop:
    if (started) {
        ret = HI_MPI_VENC_StopRecvPic(chn);
        if (ret != HI_SUCCESS)
            fprintf(stderr, "HI_MPI_VENC_StopRecvPic(%d) failed: %#x\n", chn, ret);
    }
    return exit_code;
}
