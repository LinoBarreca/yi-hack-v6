#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <errno.h>

#include "ptz.h"

#define MODEL_SUFFIX_FILE_V5 "/home/app/.camver"
#define MODEL_SUFFIX_FILE_MA "/home/yi-hack/model_suffix"
#define MODEL_SUFFIX_FILE_A2 "/tmp/sd/yi-hack/model_suffix"

int is_ptz(char *model) {
    if ((strcmp("yi_dome", model) == 0) ||
            (strcmp("yi_dome_1080p", model) == 0) ||
            (strcmp("yi_cloud_dome_1080p", model) == 0) ||
            /* v6 ships the firmware code in .camver instead of the model name */
            (strcmp("v201", model) == 0) ||
            (strcmp("h20", model) == 0) ||
            (strcmp("y19", model) == 0)) {

        return V5;

    } else if ((strcmp("h201c", model) == 0) ||
            (strcmp("h305r", model) == 0) ||
            (strcmp("y30", model) == 0) ||
            (strcmp("h307", model) == 0)) {

        return MSTAR;

    } else if (strcmp("y30qa", model) == 0) {

        return ALLWINNER;

    } else if ((strcmp("r30gb", model) == 0) ||
            (strcmp("r35gb", model) == 0) ||
            (strcmp("r40ga", model) == 0) ||
            (strcmp("h60ga", model) == 0) ||
            (strcmp("q321br_lsx", model) == 0) ||
            (strcmp("qg311r", model) == 0) ||
            (strcmp("b091qp", model) == 0)) {

        return ALLWINNER_V2;

    } else if ((strcmp("h30ga", model) == 0) ||
            (strcmp("h51ga", model) == 0) ||
            (strcmp("h52ga", model) == 0)) {

        return ALLWINNER_V2_ALT;
    } else {
        return 0;
    }
}

int get_model_suffix(char *model, int size)
{
    FILE *fileStream;

    fileStream = fopen(MODEL_SUFFIX_FILE_V5, "r");
    if (fileStream == NULL) {
        fileStream = fopen(MODEL_SUFFIX_FILE_MA, "r");
        if (fileStream == NULL) {
            fileStream = fopen(MODEL_SUFFIX_FILE_A2, "r");
            if (fileStream == NULL) {
                return -1;
            }
        }
    }
    if (fgets (model, size, fileStream) == NULL)
        return -2;
    fclose(fileStream);
    model[strcspn(model, "\r\n")] = '\0';

    return 0;
}

int ssp_init()
{
    int fd, iRet;

    fd = open("/dev/ssp", O_RDONLY);

    return fd;
}

int read_ptz(int *px, int *py)
{
    int fd_ssp;
    fd_ssp = ssp_init();
    if (fd_ssp == -1) {
        fprintf(stderr, "Error opening cpld\n");
        return -1;
    }

    int iRet;
    unsigned char pos[32];

    memset(pos, '\0', 32);
    iRet = ioctl(fd_ssp, 0x6d01, &pos);
    if (iRet < 0) {
        fprintf(stderr, "Error getting position\n");
        fprintf(stderr, "ioctl failed and returned errno %s\n", strerror(errno));
        close(fd_ssp);
        return -2;
    }

    close(fd_ssp);

    *px = *((int *) (&pos[0]));
    *py = *((int *) (&pos[4]));

    return 0;
}

/*
 * Native PTZ - drive the stock ms41909 motor driver (/dev/ssp) directly.
 *
 * Under PIPELINE=online the stock dispatch, which owns the motors, never runs,
 * so there is no queue to send the move messages to. Everything below was
 * recovered from ssp_ms41909.ko and from dispatch's own calls into it:
 *
 *   _IO('m', 1)  read state:  int[8] = { x, y, dir, -, -, running, pan steps, tilt steps }
 *   _IO('m', 2)  start move:  int[8] = { 0, 0, dir, speed (10), steps, 0, 0, 0 }
 *   _IO('m', 3)  stop
 *
 * dir is the same code dispatch's queue carries: 1 up, 2 down, 3 left, 4 right.
 * One position unit is 27 motor steps; x runs 0 (right end) .. 2950 (left end)
 * and y 0 (top) .. 800 (bottom). The driver only clamps its counters - it does
 * not stop at the end of travel, so every move is bounded here instead. The pan
 * axis has end switches on the CPLD (active low), which calibration uses.
 */

#define SSP_GET             0x6d01
#define SSP_MOVE            0x6d02
#define SSP_STOP            0x6d03
#define SSP_SPEED           10
#define SSP_STEPS_PER_UNIT  27
#define SSP_MAX_X           2950
#define SSP_MAX_Y           800
/* Extra steps past the computed end, so an uncalibrated counter still reaches it. */
#define SSP_MARGIN          (50 * SSP_STEPS_PER_UNIT)

#define CPLD_DEV            "/dev/cpld_periph"
#define CPLD_LIMIT_LEFT     _IO('p', 29)
#define CPLD_LIMIT_RIGHT    _IO('p', 30)

static int native_state(int fd, int *st)
{
    memset(st, 0, 8 * sizeof(int));
    return ioctl(fd, SSP_GET, st);
}

static int native_start(int fd, int dir, int steps)
{
    int arg[8];

    memset(arg, 0, sizeof(arg));
    arg[2] = dir;
    arg[3] = SSP_SPEED;
    arg[4] = steps;
    return ioctl(fd, SSP_MOVE, arg);
}

/* Wait for the current move to finish. limit_cmd != 0: also stop as soon as that
 * CPLD end switch closes. */
static int native_wait(int fd, unsigned long limit_cmd, int timeout_ms)
{
    int st[8];
    int cpld = -1;

    if (limit_cmd != 0)
        cpld = open(CPLD_DEV, O_RDWR);

    for (; timeout_ms > 0; timeout_ms -= 50) {
        if (cpld >= 0 && ioctl(cpld, limit_cmd) == 0) {
            ioctl(fd, SSP_STOP);
            break;
        }
        if (native_state(fd, st) < 0 || st[5] == 0)
            break;
        usleep(50 * 1000);
    }
    if (timeout_ms <= 0)
        ioctl(fd, SSP_STOP);
    if (cpld >= 0)
        close(cpld);
    return 0;
}

int native_ptz_available()
{
    return access("/dev/ssp", F_OK) == 0;
}

int native_ptz_move(int dir)
{
    int fd, st[8], units;

    fd = ssp_init();
    if (fd < 0 || native_state(fd, st) < 0) {
        fprintf(stderr, "Error opening /dev/ssp\n");
        if (fd >= 0)
            close(fd);
        return -1;
    }

    switch (dir) {
    case NATIVE_UP:    units = st[1]; break;
    case NATIVE_DOWN:  units = SSP_MAX_Y - st[1]; break;
    case NATIVE_LEFT:  units = SSP_MAX_X - st[0]; break;
    case NATIVE_RIGHT: units = st[0]; break;
    default:
        close(fd);
        return -1;
    }

    native_start(fd, dir, units * SSP_STEPS_PER_UNIT + SSP_MARGIN);
    close(fd);
    return 0;
}

int native_ptz_stop()
{
    int fd = ssp_init();

    if (fd < 0)
        return -1;
    ioctl(fd, SSP_STOP);
    close(fd);
    return 0;
}

/* Blocking move to an absolute position in driver units, pan first then tilt -
 * the driver runs one axis per command. */
int native_ptz_jump(int x, int y)
{
    int fd, st[8], d;

    if (x < 0) x = 0;
    if (x > SSP_MAX_X) x = SSP_MAX_X;
    if (y < 0) y = 0;
    if (y > SSP_MAX_Y) y = SSP_MAX_Y;

    fd = ssp_init();
    if (fd < 0 || native_state(fd, st) < 0) {
        fprintf(stderr, "Error opening /dev/ssp\n");
        if (fd >= 0)
            close(fd);
        return -1;
    }

    d = x - st[0];
    if (d != 0) {
        native_start(fd, d > 0 ? NATIVE_LEFT : NATIVE_RIGHT, abs(d) * SSP_STEPS_PER_UNIT);
        native_wait(fd, d > 0 ? CPLD_LIMIT_LEFT : CPLD_LIMIT_RIGHT, 15000);
    }
    d = y - st[1];
    if (d != 0) {
        native_start(fd, d > 0 ? NATIVE_DOWN : NATIVE_UP, abs(d) * SSP_STEPS_PER_UNIT);
        native_wait(fd, 0, 15000);
    }

    close(fd);
    return 0;
}

/* Find the end stops so the driver's counters match the mechanics: pan to the
 * right end switch (x clamps to 0), tilt fully up (y clamps to 0), then centre. */
int native_ptz_calibrate()
{
    int fd = ssp_init();

    if (fd < 0) {
        fprintf(stderr, "Error opening /dev/ssp\n");
        return -1;
    }
    native_start(fd, NATIVE_RIGHT, SSP_MAX_X * SSP_STEPS_PER_UNIT + SSP_MARGIN);
    native_wait(fd, CPLD_LIMIT_RIGHT, 15000);
    native_start(fd, NATIVE_UP, SSP_MAX_Y * SSP_STEPS_PER_UNIT + SSP_MARGIN);
    native_wait(fd, 0, 15000);
    close(fd);

    return native_ptz_jump(SSP_MAX_X / 2, SSP_MAX_Y / 2);
}
