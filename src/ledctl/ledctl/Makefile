# ledctl talks to /dev/cpld_periph through ioctl() and nothing else - no SDK, no
# MPP, no external library. It ships in FLASH (rescue and early boot need it),
# so keep it that way: every dependency added here is one that has to exist
# before the payload is mounted.

CFLAGS  += -Wall -O2 -march=armv5te -mcpu=arm926ej-s -mno-unaligned-access \
           -ffunction-sections -fdata-sections
LDFLAGS += -Wl,--gc-sections

all: ledctl

ledctl: ledctl.o
	$(CC) $(LDFLAGS) -o $@ $^

ledctl.o: ledctl.c cpld_periph.h

clean:
	rm -f ledctl *.o

.PHONY: all clean
