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
 * watermark - read one JPEG on stdin (or -i FILE), overlay the timestamp
 * watermark, write the JPEG back out on stdout (or -o FILE).
 *
 * Lets imggrabber and hwsnap both stay pure "produce one raw JPEG" tools: the
 * caller pipes through this when a watermark is wanted, instead of every
 * capture backend duplicating the blending code.
 */

#define _GNU_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <getopt.h>

#include "jpg2yuv.h"
#include "convert2jpg.h"
#include "add_water.h"

int debug = 0;

void print_usage(char *prog_name)
{
    fprintf(stderr, "Usage: %s [options]\n", prog_name);
    fprintf(stderr, "\t-i, --input FILE                 Read JPEG from FILE (default stdin)\n");
    fprintf(stderr, "\t-o, --output FILE                Write JPEG to FILE (default stdout)\n");
    fprintf(stderr, "\t-t, --watermark_time TIME         Set the time of the watermark (\"Y-M-D h:m:s\", default now)\n");
    fprintf(stderr, "\t-d, --debug                       Enable debug\n");
    fprintf(stderr, "\t-h, --help                        Show this help\n");
}

int main(int argc, char **argv)
{
    const char *input_path = NULL;
    const char *output_path = "stdout";
    int watermark_time = 0;
    struct tm watermark_tm;
    FILE *fin;
    unsigned char *bufferyuv;
    int width, height;
    int c;

    while (1) {
        static struct option long_options[] =
        {
            {"input",  required_argument, 0, 'i'},
            {"output",  required_argument, 0, 'o'},
            {"watermark_time",  required_argument, 0, 't'},
            {"debug",  no_argument, 0, 'd'},
            {"help",  no_argument, 0, 'h'},
            {0, 0, 0, 0}
        };
        int option_index = 0;

        c = getopt_long(argc, argv, "i:o:t:dh", long_options, &option_index);
        if (c == -1)
            break;

        switch (c) {
        case 'i':
            input_path = optarg;
            break;

        case 'o':
            output_path = optarg;
            break;

        case 't':
            {
                int d0, d1, d2, d3, d4, d5, d6;
                d0 = sscanf(optarg, "%d-%d-%d %d:%d:%d", &d1, &d2, &d3, &d4, &d5, &d6);
                if (d0 == 6) {
                    watermark_tm.tm_year = d1 - 1900;
                    watermark_tm.tm_mon = d2 - 1;
                    watermark_tm.tm_mday = d3;
                    watermark_tm.tm_hour = d4;
                    watermark_tm.tm_min = d5;
                    watermark_tm.tm_sec = d6;
                    watermark_time = 1;
                } else {
                    print_usage(argv[0]);
                    exit(EXIT_FAILURE);
                }
                break;
            }

        case 'd':
            fprintf(stderr, "Debug on\n");
            debug = 1;
            break;

        case 'h':
            print_usage(argv[0]);
            return -1;

        case '?':
            break;

        default:
            print_usage(argv[0]);
            return -1;
        }
    }

    if (input_path == NULL) {
        fin = stdin;
    } else {
        fin = fopen(input_path, "rb");
        if (fin == NULL) {
            fprintf(stderr, "Could not open file %s\n", input_path);
            return -2;
        }
    }

    if (debug) fprintf(stderr, "Decoding jpeg image\n");
    bufferyuv = JPGtoYUV(fin, &width, &height);
    if (input_path != NULL) fclose(fin);
    if (bufferyuv == NULL) {
        fprintf(stderr, "Error decoding jpeg image\n");
        return -3;
    }

    if (debug) fprintf(stderr, "Adding watermark\n");
    if (add_watermark(bufferyuv, width, height, watermark_time ? &watermark_tm : NULL) < 0) {
        fprintf(stderr, "Error adding watermark\n");
        free(bufferyuv);
        return -4;
    }

    if (debug) fprintf(stderr, "Encoding jpeg image\n");
    if (YUVtoJPG((char *)output_path, bufferyuv, width, height, width, height) < 0) {
        fprintf(stderr, "Error encoding jpeg file\n");
        free(bufferyuv);
        return -5;
    }

    free(bufferyuv);

    return 0;
}
