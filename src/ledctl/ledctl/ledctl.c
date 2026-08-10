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
 * ledctl - drive the status LEDs through cpld_periph.ko.
 *
 * This lives in FLASH, not on the payload, because the LED is the one piece of
 * user interface that has to work when nothing else does: during boot before
 * the payload is mounted, and in rescue, where there is no network and no web
 * UI and a blink pattern is the only way to tell the user what is happening.
 * The IR-cut filter and IR illuminator are the opposite case - they are useless
 * without a video pipeline - so they are driven from a separate tool on extra.
 *
 * Why a binary and not a shell script: the driver is reached by ioctl, and
 * busybox has neither an ioctl applet nor devmem (CONFIG_DEVMEM is off in both
 * of our builds). The only register poker reachable from the shell is stock's
 * /bin/himm, which can set a register but cannot animate - every blink would
 * become a shell loop paying a fork per transition, on a CPU where that costs
 * 50-70ms. Going through the driver instead, a mode is set once and the kernel
 * timer animates it for free.
 *
 * Under PIPELINE=stock the LEDs belong to rmm. We drive them during boot (the
 * window where rmm does not exist yet) and hand them over when the stock stack
 * comes up; we do not run alongside it.
 *
 * The command map in cpld_periph.h was recovered by disassembling the module.
 * The LEDs and the IR-cut are confirmed on a y20; the rest is not, which is
 * what `ledctl raw` is for - it issues an arbitrary command number so the map
 * can be walked on a real camera. One of those numbers resets the board, so raw
 * refuses it unless you ask twice; see cpld_periph.h.
 *
 * Both LEDs sit behind ONE window, so a state is a property of the PAIR, not of
 * one LED - which is what `pattern` is for: one bitmask carries both, and a boot
 * script setting a state pays one fork rather than two.
 *
 * What the pair does NOT give you is a predictable phase. Each LED has its own
 * toggle variable that the driver never initialises when a mode is set, so two
 * LEDs blinking at the same rate may come up together (one cyan blink) or
 * opposed (the colours alternating) - the same command has been observed doing
 * both. Choose a pattern for its rate and colours; never for its phase.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/ioctl.h>

#include "cpld_periph.h"

static int cpld_fd = -1;

static int cpld_open(void)
{
    /* No O_NONBLOCK games: open/release in the driver are bare returns. */
    cpld_fd = open(CPLD_DEV, O_RDWR);
    if (cpld_fd < 0) {
        fprintf(stderr, "ledctl: cannot open %s: %s\n", CPLD_DEV, strerror(errno));
        if (errno == ENOENT)
            fprintf(stderr, "ledctl: is cpld_periph.ko loaded?\n");
        return -1;
    }
    return 0;
}

/* One ioctl, reporting the driver's own return value. Several commands are
 * getters that return the pin state as the rc, so a positive rc is data, not an
 * error - only a negative rc means the call failed. */
static int cpld_cmd(unsigned int cmd, void *arg, const char *what)
{
    int rc = ioctl(cpld_fd, cmd, arg);

    if (rc < 0) {
        fprintf(stderr, "ledctl: %s failed: %s\n", what, strerror(errno));
        return -1;
    }
    return rc;
}

static int parse_int(const char *s, int lo, int hi, int *out)
{
    char *end;
    long v;

    errno = 0;
    v = strtol(s, &end, 0);
    if (errno != 0 || end == s || *end != '\0' || v < lo || v > hi) {
        fprintf(stderr, "ledctl: '%s' is not an integer in %d..%d\n", s, lo, hi);
        return -1;
    }
    *out = (int) v;
    return 0;
}

static void usage(const char *me)
{
    fprintf(stderr,
"usage: %s <command> [args]\n"
"\n"
"  pattern <mask|name>         set both LEDs at once (bitmask below)\n"
"  blue on|off                 steady on (at the current brightness) / off\n"
"  blue blink|breathe fast|slow   kernel-animated\n"
"  blue brightness <0-100>     PWM level, also used by 'blue on'\n"
"  yellow on|off               steady on / off\n"
"  yellow blink fast|slow      kernel-animated (yellow cannot breathe)\n"
"  off                         all LEDs off and held off\n"
"  restore                     release the hold, restore previous state\n"
"  status                      read back what the driver reports\n"
"  mode <blue|yellow> <n>      raw disp_type, for poking at new boards\n"
"  raw <1-31> [int-arg]        issue _IO('p', nr) directly - bring-up only\n"
"\n"
"pattern is a bitmask: OR one blue value with one yellow value. An unset field\n"
"means that LED is off, so 0 is everything off.\n"
"\n"
"  yellow (bits 0-3)          blue (bits 4-9)\n"
"    0x001  on                  0x010  on\n"
"    0x002  blink fast          0x020  blink fast\n"
"    0x004  blink slow          0x040  blink slow\n"
"                               0x080  breathe fast\n"
"                               0x100  breathe slow\n"
"\n"
"  named:  0 none          0x002 boot-early    0x010 ready\n"
"          0x020 boot-net  0x044 recovery\n"
"  (names and masks are interchangeable: 'pattern 0x002' = 'pattern boot-early')\n"
"\n"
"  e.g.  pattern 0x044   blue blink slow + yellow blink slow\n"
"        pattern 0x100   blue breathe slow, yellow off\n"
"\n"
"Setting a pattern tears the previous one down first, so switching straight\n"
"between two animated patterns lands on the one you asked for.\n"
"\n"
"Yellow has no breathe value: it is a plain GPIO with no duty to ramp, so a\n"
"'pulsing' yellow is a blink. Blue is on PWM and can genuinely ramp.\n"
"\n"
"Both LEDs sit behind ONE window, so any mask that lights both reads as a\n"
"single pale cyan rather than two indicators. Their blink PHASE is not settable:\n"
"the driver toggles each LED's own state variable and never initialises it on a\n"
"mode change, so a pair at the same rate may come up together (cyan blink) or\n"
"opposed (colours alternating), and has been seen doing both from the same\n"
"command. Do not design a pattern that depends on which.\n"
"\n"
"Animated modes keep running with no process attached - the kernel timer drives\n"
"them (10ms tick: fast toggles every 80ms, slow every 320ms).\n", me);
}

/* "fast"/"slow" -> the matching command, or 0 if the word is neither. */
static unsigned int rate_pick(const char *word, unsigned int fast, unsigned int slow)
{
    if (strcmp(word, "fast") == 0)
        return fast;
    if (strcmp(word, "slow") == 0)
        return slow;
    fprintf(stderr, "ledctl: rate must be 'fast' or 'slow', not '%s'\n", word);
    return 0;
}

static int cmd_blue(int argc, char **argv)
{
    if (argc < 1) {
        fprintf(stderr, "ledctl: blue needs on|off|blink|breathe|brightness\n");
        return 1;
    }

    if (strcmp(argv[0], "on") == 0)
        return cpld_cmd(CPLD_BLUE_ON, NULL, "blue on") < 0;
    if (strcmp(argv[0], "off") == 0)
        return cpld_cmd(CPLD_BLUE_OFF, NULL, "blue off") < 0;

    if (strcmp(argv[0], "blink") == 0 || strcmp(argv[0], "breathe") == 0) {
        int breathe = (argv[0][0] == 'b' && argv[0][1] == 'r');
        unsigned int cmd;

        if (argc < 2) {
            fprintf(stderr, "ledctl: blue %s needs fast or slow\n", argv[0]);
            return 1;
        }
        cmd = breathe
            ? rate_pick(argv[1], CPLD_BLUE_BREATHE_FAST, CPLD_BLUE_BREATHE_SLOW)
            : rate_pick(argv[1], CPLD_BLUE_BLINK_FAST, CPLD_BLUE_BLINK_SLOW);
        if (cmd == 0)
            return 1;
        return cpld_cmd(cmd, NULL, "blue animate") < 0;
    }

    if (strcmp(argv[0], "brightness") == 0) {
        int level;

        if (argc < 2 || parse_int(argv[1], 0, 100, &level) < 0)
            return 1;
        return cpld_cmd(CPLD_BLUE_BRIGHTNESS, &level, "blue brightness") < 0;
    }

    fprintf(stderr, "ledctl: unknown blue command '%s'\n", argv[0]);
    return 1;
}

static int cmd_yellow(int argc, char **argv)
{
    if (argc < 1) {
        fprintf(stderr, "ledctl: yellow needs on|off|blink\n");
        return 1;
    }

    if (strcmp(argv[0], "on") == 0)
        return cpld_cmd(CPLD_YELLOW_ON, NULL, "yellow on") < 0;
    if (strcmp(argv[0], "off") == 0)
        return cpld_cmd(CPLD_YELLOW_OFF, NULL, "yellow off") < 0;

    if (strcmp(argv[0], "blink") == 0) {
        unsigned int cmd;

        if (argc < 2) {
            fprintf(stderr, "ledctl: yellow blink needs fast or slow\n");
            return 1;
        }
        cmd = rate_pick(argv[1], CPLD_YELLOW_BLINK_FAST, CPLD_YELLOW_BLINK_SLOW);
        if (cmd == 0)
            return 1;
        return cpld_cmd(cmd, NULL, "yellow blink") < 0;
    }

    if (strcmp(argv[0], "breathe") == 0) {
        fprintf(stderr, "ledctl: yellow cannot breathe - it is a GPIO, not a PWM\n");
        return 1;
    }

    fprintf(stderr, "ledctl: unknown yellow command '%s'\n", argv[0]);
    return 1;
}

/* Raw disp_type, kept for probing a board whose effects we have not mapped.
 * On the y20: blue 2/3 = fast/slow blink, 5/6 = fast/slow breathe; yellow
 * 2/3 = fast/slow blink. */
static int cmd_mode(int argc, char **argv)
{
    int mode;

    if (argc < 2) {
        fprintf(stderr, "ledctl: mode needs <blue|yellow> <n>\n");
        return 1;
    }
    if (strcmp(argv[0], "blue") == 0) {
        if (parse_int(argv[1], 2, 6, &mode) < 0)
            return 1;
        switch (mode) {
        case 2: return cpld_cmd(CPLD_BLUE_BLINK_FAST,   NULL, "blue mode") < 0;
        case 3: return cpld_cmd(CPLD_BLUE_BLINK_SLOW,   NULL, "blue mode") < 0;
        case 5: return cpld_cmd(CPLD_BLUE_BREATHE_FAST, NULL, "blue mode") < 0;
        case 6: return cpld_cmd(CPLD_BLUE_BREATHE_SLOW, NULL, "blue mode") < 0;
        default:
            /* 4 is the flash-count type, which needs the pointer argument the
             * driver dereferences unchecked - not reachable from here. */
            fprintf(stderr, "ledctl: blue has modes 2, 3, 5 and 6 (not %d)\n", mode);
            return 1;
        }
    }
    if (strcmp(argv[0], "yellow") == 0) {
        if (parse_int(argv[1], 2, 3, &mode) < 0)
            return 1;
        return cpld_cmd(mode == 2 ? CPLD_YELLOW_BLINK_FAST : CPLD_YELLOW_BLINK_SLOW,
                        NULL, "yellow mode") < 0;
    }

    fprintf(stderr, "ledctl: mode needs 'blue' or 'yellow', not '%s'\n", argv[0]);
    return 1;
}

/* Every combination of the two LEDs, numbered. A boot state is a property of
 * the PAIR - they share one window - so it is set as a single command: one fork
 * for a boot script instead of two, and the states are defined here rather than
 * spread across the scripts that use them.
 *
 * The order is blue-major: blue cycles every 4 entries, yellow every 1, which
 * is what makes the printed grid a plain 6x4 lookup. Names are aliases onto the
 * same numbers, so `pattern 3` and `pattern boot-early` are one and the same. */
static const struct { const char *name; int mask; } pattern_names[] = {
    { "none",       LEDM_NONE       },
    { "boot-early", LEDM_BOOT_EARLY },
    { "boot-net",   LEDM_BOOT_NET   },
    { "recovery",   LEDM_RECOVERY   },
    { "ready",      LEDM_READY      },
};
#define PATTERN_NAMES (int)(sizeof(pattern_names) / sizeof(pattern_names[0]))

/* Exactly one bit, or none, may be set in a field - the states are mutually
 * exclusive, so two bits is a caller bug rather than something to resolve. */
static int one_hot(int field, const char *which)
{
    if (field != 0 && (field & (field - 1)) != 0) {
        fprintf(stderr, "ledctl: more than one %s state selected (0x%03x)\n", which, field);
        return -1;
    }
    return 0;
}

static unsigned int yellow_cmd_of(int mask)
{
    if (mask & LEDM_Y_ON)         return CPLD_YELLOW_ON;
    if (mask & LEDM_Y_BLINK_FAST) return CPLD_YELLOW_BLINK_FAST;
    if (mask & LEDM_Y_BLINK_SLOW) return CPLD_YELLOW_BLINK_SLOW;
    return CPLD_YELLOW_OFF;
}

static unsigned int blue_cmd_of(int mask)
{
    if (mask & LEDM_B_ON)           return CPLD_BLUE_ON;
    if (mask & LEDM_B_BLINK_FAST)   return CPLD_BLUE_BLINK_FAST;
    if (mask & LEDM_B_BLINK_SLOW)   return CPLD_BLUE_BLINK_SLOW;
    if (mask & LEDM_B_BREATHE_FAST) return CPLD_BLUE_BREATHE_FAST;
    if (mask & LEDM_B_BREATHE_SLOW) return CPLD_BLUE_BREATHE_SLOW;
    return CPLD_BLUE_OFF;
}

static int cmd_pattern(int argc, char **argv)
{
    int mask = -1, i;

    if (argc < 1) {
        fprintf(stderr, "ledctl: pattern needs a bitmask (0-0x%03x) or a name\n", LEDM_ALL);
        return 1;
    }

    for (i = 0; i < PATTERN_NAMES; i++) {
        if (strcmp(argv[0], pattern_names[i].name) == 0) {
            mask = pattern_names[i].mask;
            break;
        }
    }
    if (mask < 0) {
        /* parse_int takes 0x..., so a mask reads naturally in hex. */
        if (parse_int(argv[0], 0, LEDM_ALL, &mask) < 0)
            return 1;
    }

    if (one_hot(mask & LEDM_Y_MASK, "yellow") < 0 ||
        one_hot(mask & LEDM_B_MASK, "blue") < 0)
        return 1;

    /* Go through all-off before applying the new state. Switching straight from
     * one animated pattern to another leaves the driver mid-animation and the
     * result is visibly not the pattern asked for; the LEDs settle correctly
     * when the previous one is torn down first. Cheap - these are ioctls on an
     * already-open fd, not forks. */
    if (cpld_cmd(CPLD_YELLOW_OFF, NULL, "pattern (yellow off)") < 0 ||
        cpld_cmd(CPLD_BLUE_OFF,   NULL, "pattern (blue off)") < 0)
        return 1;

    if (mask == LEDM_NONE)
        return 0;

    /* Yellow first: it is the plain GPIO, so it settles immediately. */
    if (cpld_cmd(yellow_cmd_of(mask), NULL, "pattern (yellow)") < 0)
        return 1;
    return cpld_cmd(blue_cmd_of(mask), NULL, "pattern (blue)") < 0;
}

static int cmd_status(void)
{
    int rc;

    /* Getters return the value as the ioctl rc. Report failures individually
     * rather than bailing: on an unmapped board some of these may not answer,
     * and seeing which ones do is the point during bring-up. */
    rc = ioctl(cpld_fd, CPLD_IRCUT_READ, NULL);
    if (rc < 0)
        printf("ircut    : unreadable (%s)\n", strerror(errno));
    else
        printf("ircut    : %d\n", rc);

    rc = ioctl(cpld_fd, CPLD_GPIO4_6_READ, NULL);
    if (rc < 0)
        printf("gpio4_6  : unreadable (%s)\n", strerror(errno));
    else
        printf("gpio4_6  : %d (unreliable - reads its own pull-up)\n", rc);

    rc = ioctl(cpld_fd, CPLD_AMP_READ, NULL);
    if (rc < 0)
        printf("spk amp  : unreadable (%s)\n", strerror(errno));
    else
        printf("spk amp  : %d\n", rc);

    return 0;
}

/* Bring-up escape hatch: issue any command number so the disassembled map can
 * be walked against the real board. Deliberately refuses 31, which stores a pid
 * the module never signals, and 7/13, whose kernel-side pointer deref makes a
 * wrong argument an oops rather than an error. */
static int cmd_raw(int argc, char **argv)
{
    int nr, arg = 0, rc;

    if (argc < 1 || parse_int(argv[0], CPLD_NR_MIN, CPLD_NR_MAX, &nr) < 0)
        return 1;

    if (nr == 31) {
        fprintf(stderr, "ledctl: refusing 31 (stores a pid nothing ever signals)\n");
        return 1;
    }
    if (nr == 7 || nr == 13) {
        fprintf(stderr, "ledctl: refusing %d - it dereferences the user pointer\n", nr);
        fprintf(stderr, "ledctl: in kernel context with no copy_from_user\n");
        return 1;
    }
    /* Driving GPIO4_6 high reset the y20 every time it was tried. Gated behind
     * an explicit opt-in so it cannot be reached by walking the table, which is
     * exactly how it was hit the first time. */
    if (nr == 24 && getenv("LEDCTL_ALLOW_GPIO4_6") == NULL) {
        fprintf(stderr, "ledctl: refusing 24 - driving GPIO4_6 high resets this board.\n");
        fprintf(stderr, "ledctl: set LEDCTL_ALLOW_GPIO4_6=1 if you really mean it.\n");
        return 1;
    }

    if (argc >= 2) {
        if (parse_int(argv[1], 0, 0x7fffffff, &arg) < 0)
            return 1;
        rc = ioctl(cpld_fd, CPLD_IO(nr), &arg);
    } else {
        rc = ioctl(cpld_fd, CPLD_IO(nr), NULL);
    }

    if (rc < 0) {
        fprintf(stderr, "ledctl: raw %d failed: %s\n", nr, strerror(errno));
        return 1;
    }
    printf("raw %d -> %d\n", nr, rc);
    return 0;
}

int main(int argc, char **argv)
{
    int ret;

    if (argc < 2) {
        usage(argv[0]);
        return 1;
    }
    if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
        usage(argv[0]);
        return 0;
    }

    if (cpld_open() < 0)
        return 1;

    if (strcmp(argv[1], "blue") == 0)
        ret = cmd_blue(argc - 2, argv + 2);
    else if (strcmp(argv[1], "yellow") == 0)
        ret = cmd_yellow(argc - 2, argv + 2);
    else if (strcmp(argv[1], "pattern") == 0)
        ret = cmd_pattern(argc - 2, argv + 2);
    else if (strcmp(argv[1], "mode") == 0)
        ret = cmd_mode(argc - 2, argv + 2);
    else if (strcmp(argv[1], "off") == 0)
        ret = cpld_cmd(CPLD_LEDS_OFF_LOCK, NULL, "leds off") < 0;
    else if (strcmp(argv[1], "restore") == 0)
        ret = cpld_cmd(CPLD_LEDS_RESTORE, NULL, "leds restore") < 0;
    else if (strcmp(argv[1], "status") == 0)
        ret = cmd_status();
    else if (strcmp(argv[1], "raw") == 0)
        ret = cmd_raw(argc - 2, argv + 2);
    else {
        fprintf(stderr, "ledctl: unknown command '%s'\n", argv[1]);
        usage(argv[0]);
        ret = 1;
    }

    close(cpld_fd);
    return ret;
}
