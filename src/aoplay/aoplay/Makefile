SDK      = ../../hisdk/mpp
REL_LIB  = $(SDK)/lib
COMMON   = $(SDK)/sample/common

# Same chip/codec flags campipe uses. HI_ACODEC_TYPE_INNER selects the inner
# audio codec path in SAMPLE_COMM_AUDIO_CfgAcodec (this SoC's built-in ACODEC).
DEFS = -Dhi3518e -DHICHIP=0x3518E200 -Dhi3518ev200 -DCHIP_ID=CHIP_HI3518E_V200 \
       -DSENSOR_TYPE=OMNIVISION_OV9732_DC_720P_30FPS -DISP_V2 -DHI_ACODEC_TYPE_INNER \
       -DHI_XXXX -DENABLE_JPEGEDCF \
       -DVER_X=1 -DVER_Y=0 -DVER_Z=0 -DVER_P=0 -DVER_B=10

CFLAGS  += -Wall -O2 -march=armv5te -mcpu=arm926ej-s -mno-unaligned-access \
           -fno-aggressive-loop-optimizations -ffunction-sections -fdata-sections \
           -I$(SDK)/include -I$(COMMON) $(DEFS)

# SYS/VB init + the audio helpers (CfgAcodec / StartAo / StopAo). Unused paths in
# sample_comm_audio.c (AENC/ADEC/AAC/file examples) are dropped by --gc-sections.
COMM_OBJ = sample_comm_sys.o sample_comm_audio.o

# MPI + the audio VQE/resample libs (libmpi's AO objects reference them). Grouped
# so ld rescans for any cross-dependency, like campipe does for libmd/libive.
LDLIBS = -Wl,--start-group $(REL_LIB)/libmpi.a $(REL_LIB)/libVoiceEngine.a \
         $(REL_LIB)/libupvqe.a $(REL_LIB)/libdnvqe.a -Wl,--end-group \
         -lpthread -lm -ldl
LDFLAGS += -Wl,--gc-sections

all: aoplay

aoplay: aoplay.o $(COMM_OBJ)
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

aoplay.o: aoplay.c
	$(CC) $(CFLAGS) -c -o $@ $<

sample_comm_%.o: $(COMMON)/sample_comm_%.c
	$(CC) $(CFLAGS) -Wno-unused -Wno-unused-but-set-variable -c -o $@ $<

clean:
	rm -f aoplay *.o
