SDK      = ../../hisdk/mpp
REL_LIB  = $(SDK)/lib
COMMON   = $(SDK)/sample/common

# AAC-LC encoder for the forward audio track (mic -> AENC -> /tmp/aac_audio_fifo).
# The Hi3518EV200 has NO audio encoder in silicon and none in the SDK: libmpi
# exports HI_MPI_AENC_VoiceInit (G711/G726/ADPCM/LPCM) but no AacInit, and
# mpp/lib ships no AAC library. Stock solves this by statically linking a
# HiSilicon FDK-AAC build (HiBVT_AUDIO V3.0.3.3) into rmm and registering it via
# HI_MPI_AENC_RegeisterEncoder; we do the same thing with a redistributable
# encoder. vo-aacenc is the VisualOn AAC-LC encoder: fixed-point with ARMv5E
# assembly (this CPU is an ARM926EJ-S, i.e. armv5te - it has no FPU, so a
# float encoder would be far more expensive), it emits ADTS frames directly
# (what ADTSAudioFifoSource expects), and Apache-2.0 sits fine under our GPLv3.
#
# Fetched, checksummed and cross-built by ../init.campipe - not from here. Same split
# as every other external tarball in the tree (init.jq, init.busybox): init gets the
# sources, the Makefile only builds. The configure flags, and why NOT --enable-armv5e,
# are documented there next to the invocation.
AACENC     = vo-aacenc-0.1.3
AACENC_LIB = $(AACENC)/.libs/libvo-aacenc.a
AACENC_INC = $(AACENC)/common/include

# Chip/sensor selection. The y20 sensor is a SOI JXF22 (1080p25 DVP, i2c 0x80),
# identified by letting stock rmm probe it: the SDK has NO F22 driver, so campipe
# dlopens the stock /home/app/locallib/libsns_f22.so plugin (see campipe.c) and
# no libsns_*.a is linked. SENSOR_TYPE is still set to the ov9732 because its
# DC/CMOS attrs in the SDK sample tables match the F22 electrical interface
# (10-bit DC parallel); campipe overrides every size-dependent attr itself.
# These -D flags are exactly what the SDK's sample/Makefile.param derives for this
# combination (HIARCH=hi3518e, CHIP_ID=CHIP_HI3518E_V200, inner audio codec).
DEFS = -Dhi3518e -DHICHIP=0x3518E200 -Dhi3518ev200 -DCHIP_ID=CHIP_HI3518E_V200 \
       -DSENSOR_TYPE=OMNIVISION_OV9732_DC_720P_30FPS -DISP_V2 -DHI_ACODEC_TYPE_INNER \
       -DHI_XXXX -DENABLE_JPEGEDCF \
       -DVER_X=1 -DVER_Y=0 -DVER_Z=0 -DVER_P=0 -DVER_B=10

CFLAGS  += -Wall -O2 -march=armv5te -mcpu=arm926ej-s -mno-unaligned-access \
           -fno-aggressive-loop-optimizations -ffunction-sections -fdata-sections \
           -I$(SDK)/include -I$(COMMON) -I$(AACENC_INC) $(DEFS)

# Reuse the SDK's proven MPP init helpers (SYS/VB, VI, VPSS, VENC, ISP) plus the
# audio helpers (CfgAcodec/StartAo for the speaker). --gc-sections drops the unused
# AENC/ADEC/AAC/file paths in sample_comm_audio.o.
COMM_OBJ = sample_comm_sys.o sample_comm_vi.o sample_comm_vpss.o \
           sample_comm_venc.o sample_comm_isp.o sample_comm_audio.o

# Static link (the camera has no MPP .so; rmm static-links the same libs). Order
# matters: MPI first, then ISP algo libs + sensor, then audio VQE (pulled in by
# libmpi even for video-only), then libc helpers.
# libmd.a (motion detection, ivs_md.o) calls HI_MPI_IVE_* which live in libive.a,
# and libive.a in turn needs libmpi.a helpers - a circular dependency, so wrap the
# three in a link group and let ld rescan them until resolved (order-independent).
LDLIBS = -Wl,--start-group $(REL_LIB)/libmpi.a $(REL_LIB)/libive.a $(REL_LIB)/libmd.a -Wl,--end-group \
         $(REL_LIB)/libisp.a \
         $(REL_LIB)/lib_hiae.a $(REL_LIB)/lib_hiawb.a $(REL_LIB)/lib_hiaf.a \
         $(REL_LIB)/lib_hidefog.a $(REL_LIB)/lib_cmoscfg.a $(REL_LIB)/lib_iniparser.a \
         $(REL_LIB)/libVoiceEngine.a $(REL_LIB)/libupvqe.a $(REL_LIB)/libdnvqe.a \
         $(AACENC_LIB) \
         -lpthread -lm -ldl
# -rdynamic: the dlopen'd stock sensor plugin resolves HI_MPI_*_Sensor*CallBack
# from this executable. The -u anchors force those objects in even though no
# static code references them (the plugin is the only caller).
LDFLAGS += -Wl,--gc-sections -rdynamic \
           -Wl,-u,HI_MPI_ISP_SensorRegCallBack -Wl,-u,HI_MPI_ISP_SensorUnRegCallBack \
           -Wl,-u,HI_MPI_AE_SensorRegCallBack  -Wl,-u,HI_MPI_AE_SensorUnRegCallBack \
           -Wl,-u,HI_MPI_AWB_SensorRegCallBack -Wl,-u,HI_MPI_AWB_SensorUnRegCallBack

all: campipe

campipe: campipe.o $(COMM_OBJ) $(AACENC_LIB)
	$(CC) $(LDFLAGS) -o $@ campipe.o $(COMM_OBJ) $(LDLIBS)

campipe.o: campipe.c $(AACENC_LIB)
	$(CC) $(CFLAGS) -c -o $@ $<

# SDK helper objects, compiled from the vendored sample sources.
sample_comm_%.o: $(COMMON)/sample_comm_%.c
	$(CC) $(CFLAGS) -Wno-unused -Wno-unused-but-set-variable -c -o $@ $<

# The encoder is a PREREQUISITE here, never a thing this Makefile builds: no network
# and no third-party configure in the build step. If it is missing, say so and stop -
# a build that silently downloaded would hide a broken/skipped init.
$(AACENC_LIB):
	@echo "campipe: $(AACENC_LIB) is missing." >&2
	@echo "         Run ../init.campipe - it fetches, verifies and cross-builds vo-aacenc." >&2
	@false

# `clean` deliberately leaves the vo-aacenc tree alone: compile.campipe runs
# `make clean && make` on every build, and re-configuring/rebuilding the encoder
# each time would cost minutes for nothing. Use distclean to force a refetch.
clean:
	rm -f campipe *.o

distclean: clean
	rm -rf $(AACENC) $(AACENC).tar.gz
