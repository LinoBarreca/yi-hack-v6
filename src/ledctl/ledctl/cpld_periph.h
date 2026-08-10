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
 * cpld_periph - the stock board peripheral driver's ioctl interface.
 *
 * The Yi boards drive their status LEDs, IR-cut filter and IR illuminator from
 * cpld_periph.ko (a GPL module shipped in flash as /home/app/localko), which
 * exposes the misc device /dev/cpld_periph. Everything below was recovered by
 * reverse-engineering that module - it ships without headers. Under PIPELINE=stock
 * these are rmm's to drive; we use them only where rmm is absent.
 *
 * Confirmed on hardware (y20): both LEDs and all six animated modes, and the
 * IR-cut in both directions. Everything else below is still disassembly only -
 * confirm with `ledctl raw <n>` before trusting it.
 *
 * !!! DO NOT drive GPIO4_6 high (commands 24/26 below). On the y20 it RESET THE
 * CAMERA within seconds, every time. See the warning at those commands.
 *
 * The two LEDs share ONE physical window, so lighting both reads as pale cyan
 * rather than as two separate indicators - worth knowing before designing any
 * pattern that uses them together. They also animate in phase, not alternately.
 *
 * The driver holds ONE global copy of the LED state, and open/release are bare
 * `return 0` (no owner, no refcount), so it will not arbitrate between two
 * writers. It does not need to: we drive the LEDs during boot and hand them to
 * rmm when the stock stack comes up, rather than running alongside it.
 *
 * The animations run on a kernel timer inside the module: set a mode once and
 * it keeps going with no further userspace work. Note the two LEDs are not
 * symmetric - blue is on a PWM channel so it can genuinely ramp brightness,
 * while yellow is a plain GPIO that can only toggle.
 */

#ifndef CPLD_PERIPH_H
#define CPLD_PERIPH_H

#define CPLD_DEV            "/dev/cpld_periph"

/* _IO('p', nr). The driver checks bits 8-15 == 'p' and accepts nr 1..31. */
#define CPLD_MAGIC          'p'
#define CPLD_IO(nr)         _IO(CPLD_MAGIC, (nr))
#define CPLD_NR_MIN         1
#define CPLD_NR_MAX         31

/* Blue LED - PWM channel 1. Duty is derived from the brightness set by
 * CPLD_BLUE_BRIGHTNESS (duty = 3000 - 30*value, i.e. the PWM is active low). */
#define CPLD_BLUE_ON        CPLD_IO(1)
#define CPLD_BLUE_OFF       CPLD_IO(2)
#define CPLD_BLUE_BLINK_FAST   CPLD_IO(3)   /* verified on y20 */
#define CPLD_BLUE_BLINK_SLOW   CPLD_IO(4)   /* verified on y20 */
#define CPLD_BLUE_BREATHE_FAST CPLD_IO(5)   /* verified on y20 - real PWM ramp */
#define CPLD_BLUE_BREATHE_SLOW CPLD_IO(6)   /* verified on y20 - real PWM ramp */
#define CPLD_BLUE_FLASH_N   CPLD_IO(7)   /* arg: int* count - see WARNING below  */
#define CPLD_BLUE_BRIGHTNESS CPLD_IO(8)  /* arg: int* 0..100 (copy_from_user)    */

/* Yellow LED - GPIO0_2, ACTIVE LOW (the driver writes 0 to light it). */
#define CPLD_YELLOW_ON      CPLD_IO(9)
#define CPLD_YELLOW_OFF     CPLD_IO(10)
/* Yellow has no breathe: it is a plain GPIO, so there is no duty to ramp. */
#define CPLD_YELLOW_BLINK_FAST CPLD_IO(11) /* verified on y20 */
#define CPLD_YELLOW_BLINK_SLOW CPLD_IO(12) /* verified on y20 */
#define CPLD_YELLOW_FLASH_N CPLD_IO(13)  /* arg: int* count - see WARNING below  */

/* WARNING - the flash-count commands (7 and 13) dereference the user pointer
 * directly in kernel context, with no copy_from_user (unlike 8 and 19, which do
 * it properly). A bad address is an oops, not an EFAULT. Prefer the animated
 * modes above; if you must use these, pass the address of a real int. */

#define CPLD_IN_GPIO0_0     CPLD_IO(14)  /* read one input pin                   */
#define CPLD_IN_GPIO6_3_4   CPLD_IO(15)  /* read two input pins                  */

/* GPIO6_6 = speaker amplifier enable. This is the same pin campipe drives via
 * /dev/mem from the audio_hw.conf table (found independently by register diff);
 * the driver offering it here is a cross-check, not a reason to change that
 * path, which is validated on hardware. */
#define CPLD_AMP_ON         CPLD_IO(16)
#define CPLD_AMP_OFF        CPLD_IO(17)
#define CPLD_AMP_READ       CPLD_IO(18)

/* PWM channel 0 - a SECOND, independent PWM, not the blue LED (which is channel
 * 1). Same 0..100 scale, duty = value*30 against a 3000 period. Nothing else in
 * the table accounts for it, and an IR illuminator is exactly the kind of load
 * that wants a current-limited PWM drive rather than a hard-on GPIO - which is
 * the leading theory for the GPIO4_6 reset below. Unconfirmed. */
#define CPLD_PWM0_SET       CPLD_IO(19)  /* arg: int* 0..100 (copy_from_user)    */
#define CPLD_PWM0_GET       CPLD_IO(20)  /* arg: int* (copy_to_user)             */

/* IR-cut filter - a LATCHING dual-coil motor on GPIO8_0 (cathode) / GPIO8_1
 * (anode). The driver does the whole pulse itself: energise, msleep(200),
 * release both ends. Never hold a coil energised. */
#define CPLD_IRCUT_NIGHT    CPLD_IO(21)  /* filter out - IR mode                 */
#define CPLD_IRCUT_DAY      CPLD_IO(22)  /* filter in  - normal mode             */
#define CPLD_IRCUT_READ     CPLD_IO(23)  /* returns 1, 2 or 3                    */

/* GPIO4_6 - !!! DANGEROUS ON THE y20, DO NOT DRIVE HIGH !!!
 *
 * Command 24 (drive high) RESET THE CAMERA within seconds of being issued, and
 * did it every time. The board came back up clean on its own, so it is not
 * destructive, but nothing should issue 24 until we know why.
 *
 * Not a watchdog timeout: that margin is 60s and the reset came far sooner. The
 * leading theory is a brownout - an IR LED array is a heavy load, and if this
 * pin hard-enables one on a supply with no headroom, the rail dips and the SoC
 * resets. That fits the illuminator being meant to run off the current-limited
 * PWM channel 0 above rather than off a raw GPIO. The alternative - that the pin
 * is a reset or power-enable line and has nothing to do with IR - is not ruled
 * out.
 *
 * Note command 26 (read) is ALSO not trustworthy here: out_pin_gpio_read flips
 * the pin to an input to sample it, so a pull-up reads back 1 whatever the
 * driver was doing. It read 1 on a camera that was plainly not in night mode. */
#define CPLD_GPIO4_6_HIGH   CPLD_IO(24)  /* !!! resets the y20 - see above       */
#define CPLD_GPIO4_6_LOW    CPLD_IO(25)
#define CPLD_GPIO4_6_READ   CPLD_IO(26)  /* unreliable - reads its own pull-up   */

#define CPLD_LEDS_OFF_LOCK  CPLD_IO(27)  /* all LEDs off and held off            */
#define CPLD_LEDS_RESTORE   CPLD_IO(28)  /* release the lock, restore state      */

#define CPLD_IN_GPIO7_0     CPLD_IO(29)  /* limit switch? (PTZ - stage E)        */
#define CPLD_IN_GPIO7_1     CPLD_IO(30)  /* limit switch? (PTZ - stage E)        */

/* Stores a pid the module never signals - gpio_isr only printks. Vestigial in
 * this build; there is nothing to register for, so do not call it. */
#define CPLD_SET_CALLER_PID CPLD_IO(31)

/* ---- pattern bitmask -------------------------------------------------------
 *
 * A state is a property of BOTH LEDs (one window), so it is expressed as one
 * value: 4 bits of yellow in the low nibble, 6 bits of blue above it, one-hot
 * within each field. An unset field means that LED is off, which makes 0 "all
 * off" without needing a code for it, and lets a caller OR the two halves
 * together instead of looking a combination up in a table.
 *
 * Each field keeps a spare bit: yellow gains a mode only if the hardware ever
 * grows one, blue has room for a sixth.
 */
#define LEDM_Y_ON            0x001
#define LEDM_Y_BLINK_FAST    0x002
#define LEDM_Y_BLINK_SLOW    0x004
#define LEDM_Y_MASK          0x00f

#define LEDM_B_ON            0x010
#define LEDM_B_BLINK_FAST    0x020
#define LEDM_B_BLINK_SLOW    0x040
#define LEDM_B_BREATHE_FAST  0x080
#define LEDM_B_BREATHE_SLOW  0x100
#define LEDM_B_MASK          0x3f0

#define LEDM_ALL             (LEDM_Y_MASK | LEDM_B_MASK)

/* Named states. Numbers and names are interchangeable at the command line. */
#define LEDM_NONE            0
#define LEDM_BOOT_EARLY      LEDM_Y_BLINK_FAST
#define LEDM_BOOT_NET        LEDM_B_BLINK_FAST
#define LEDM_RECOVERY        (LEDM_B_BLINK_SLOW | LEDM_Y_BLINK_SLOW)
#define LEDM_READY           LEDM_B_ON

#endif /* CPLD_PERIPH_H */
