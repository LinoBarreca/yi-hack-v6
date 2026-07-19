SDK_DIR = ../../hisdk/mpp

CFLAGS  += -I$(SDK_DIR)/include -march=armv5te -mcpu=arm926ej-s -O2 -Wall \
           -ffunction-sections -fdata-sections
# libmpi.a pulls in audio VQE symbols even for video-only use; the VQE static
# libs satisfy them and --gc-sections drops the unused code from the binary.
# MPP libs by explicit .a path: the camera has no libmpi.so (rmm static-links),
# and -lmpi would silently pick the SDK's .so over the .a.
LDFLAGS += -Wl,--gc-sections
LDLIBS  += $(SDK_DIR)/lib/libmpi.a $(SDK_DIR)/lib/libupvqe.a \
           $(SDK_DIR)/lib/libdnvqe.a $(SDK_DIR)/lib/libVoiceEngine.a \
           -lpthread -lm -ldl -lrt

all: hwsnap

hwsnap: hwsnap.o
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

hwsnap.o: hwsnap.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f hwsnap hwsnap.o
