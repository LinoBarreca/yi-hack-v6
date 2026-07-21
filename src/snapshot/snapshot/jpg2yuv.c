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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <jpeglib.h>

#include "jpg2yuv.h"

unsigned char *JPGtoYUV(FILE *input, int *out_width, int *out_height)
{
    struct jpeg_decompress_struct cinfo;
    struct jpeg_error_mgr jerr;
    int w, h, max_v, iMCU_h, y_stride_h, c_stride_h, y_w, c_w, i, j;
    unsigned char *y_data, *cb_data, *cr_data, *out;
    JSAMPROW *y_buf, *cb_buf, *cr_buf;

    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_decompress(&cinfo);
    jpeg_stdio_src(&cinfo, input);
    jpeg_read_header(&cinfo, TRUE);

    // Standard baseline 4:2:0 (2x2,1x1,1x1) is what every producer in this codebase
    // writes (imggrabber, hwsnap, and this tool's own output). Reject anything else
    // instead of silently misreading the component layout below.
    if (cinfo.num_components != 3 ||
        cinfo.comp_info[0].h_samp_factor != 2 || cinfo.comp_info[0].v_samp_factor != 2 ||
        cinfo.comp_info[1].h_samp_factor != 1 || cinfo.comp_info[1].v_samp_factor != 1 ||
        cinfo.comp_info[2].h_samp_factor != 1 || cinfo.comp_info[2].v_samp_factor != 1) {
        fprintf(stderr, "Unsupported JPEG sampling (expected baseline 4:2:0)\n");
        jpeg_destroy_decompress(&cinfo);
        return NULL;
    }

    cinfo.dct_method = JDCT_FASTEST;
    cinfo.raw_data_out = TRUE;
    jpeg_start_decompress(&cinfo);

    w = cinfo.output_width;
    h = cinfo.output_height;
    max_v = cinfo.max_v_samp_factor;
    iMCU_h = DCTSIZE * max_v;

    y_stride_h = ((h + iMCU_h - 1) / iMCU_h) * iMCU_h;
    c_stride_h = y_stride_h / 2;
    y_w = cinfo.comp_info[0].width_in_blocks * DCTSIZE;
    c_w = cinfo.comp_info[1].width_in_blocks * DCTSIZE;

    y_data = malloc((size_t)y_w * y_stride_h);
    cb_data = malloc((size_t)c_w * c_stride_h);
    cr_data = malloc((size_t)c_w * c_stride_h);
    y_buf = malloc(y_stride_h * sizeof(JSAMPROW));
    cb_buf = malloc(c_stride_h * sizeof(JSAMPROW));
    cr_buf = malloc(c_stride_h * sizeof(JSAMPROW));
    if (!y_data || !cb_data || !cr_data || !y_buf || !cb_buf || !cr_buf) {
        fprintf(stderr, "Unable to allocate memory\n");
        goto fail;
    }
    for (i = 0; i < y_stride_h; i++) y_buf[i] = y_data + (size_t)i * y_w;
    for (i = 0; i < c_stride_h; i++) {
        cb_buf[i] = cb_data + (size_t)i * c_w;
        cr_buf[i] = cr_data + (size_t)i * c_w;
    }

    i = 0;
    while (i < y_stride_h) {
        JSAMPARRAY planes[3];
        planes[0] = y_buf + i;
        planes[1] = cb_buf + i / 2;
        planes[2] = cr_buf + i / 2;
        jpeg_read_raw_data(&cinfo, planes, iMCU_h);
        i += iMCU_h;
    }
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);

    out = malloc((size_t)w * h * 3 / 2);
    if (!out) {
        fprintf(stderr, "Unable to allocate memory\n");
        free(y_data); free(cb_data); free(cr_data);
        free(y_buf); free(cb_buf); free(cr_buf);
        return NULL;
    }
    for (i = 0; i < h; i++) {
        memcpy(out + (size_t)w * i, y_data + (size_t)y_w * i, w);
    }
    for (i = 0; i < h / 2; i++) {
        for (j = 0; j < w / 2; j++) {
            out[(size_t)w * h + w * i + 2 * j]     = cb_data[(size_t)c_w * i + j];
            out[(size_t)w * h + w * i + 2 * j + 1] = cr_data[(size_t)c_w * i + j];
        }
    }

    free(y_data); free(cb_data); free(cr_data);
    free(y_buf); free(cb_buf); free(cr_buf);

    *out_width = w;
    *out_height = h;
    return out;

fail:
    free(y_data); free(cb_data); free(cr_data);
    free(y_buf); free(cb_buf); free(cr_buf);
    jpeg_destroy_decompress(&cinfo);
    return NULL;
}
