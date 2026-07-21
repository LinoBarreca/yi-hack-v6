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

#ifndef __JPG2YUV_H__
#define __JPG2YUV_H__

#include <stdio.h>

// Decodes a baseline JPEG (standard 4:2:0, i.e. 2x2,1x1,1x1 sampling -- what every
// producer in this codebase writes) straight to an NV12 buffer: Y plane row-major,
// followed by a width*height/2 interleaved-UV plane -- the exact layout frame_decode()
// (imggrabber.c) already produces, so add_watermark()/YUVtoJPG() need no changes.
// Uses libjpeg's raw-data API (no upsampling, no color-space conversion) since a
// subsampled buffer is what's wanted anyway -- see plan step 0 for why: the naive
// JCS_YCbCr decode path is ~6-12x slower and OOMs on camera-class RAM.
// Returns a malloc'ed buffer, or NULL on error. Caller frees it.
unsigned char *JPGtoYUV(FILE *input, int *out_width, int *out_height);

#endif
