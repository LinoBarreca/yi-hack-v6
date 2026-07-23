SDK      = ../../hisdk/mpp
REL_LIB  = $(SDK)/lib
COMMON   = $(SDK)/sample/common

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
           -I$(SDK)/include -I$(COMMON) $(DEFS)

# Reuse the SDK's proven MPP init helpers (SYS/VB, VI, VPSS, VENC, ISP). None of
# these five reference the VO/audio/IVE helpers, so we compile just them.
COMM_OBJ = sample_comm_sys.o sample_comm_vi.o sample_comm_vpss.o \
           sample_comm_venc.o sample_comm_isp.o

# Static link (the camera has no MPP .so; rmm static-links the same libs). Order
# matters: MPI first, then ISP algo libs + sensor, then audio VQE (pulled in by
# libmpi even for video-only), then libc helpers.
LDLIBS = $(REL_LIB)/libmpi.a $(REL_LIB)/libive.a $(REL_LIB)/libmd.a \
         $(REL_LIB)/libisp.a \
         $(REL_LIB)/lib_hiae.a $(REL_LIB)/lib_hiawb.a $(REL_LIB)/lib_hiaf.a \
         $(REL_LIB)/lib_hidefog.a $(REL_LIB)/lib_cmoscfg.a $(REL_LIB)/lib_iniparser.a \
         $(REL_LIB)/libVoiceEngine.a $(REL_LIB)/libupvqe.a $(REL_LIB)/libdnvqe.a \
         -lpthread -lm -ldl
# -rdynamic: the dlopen'd stock sensor plugin resolves HI_MPI_*_Sensor*CallBack
# from this executable. The -u anchors force those objects in even though no
# static code references them (the plugin is the only caller).
LDFLAGS += -Wl,--gc-sections -rdynamic \
           -Wl,-u,HI_MPI_ISP_SensorRegCallBack -Wl,-u,HI_MPI_ISP_SensorUnRegCallBack \
           -Wl,-u,HI_MPI_AE_SensorRegCallBack  -Wl,-u,HI_MPI_AE_SensorUnRegCallBack \
           -Wl,-u,HI_MPI_AWB_SensorRegCallBack -Wl,-u,HI_MPI_AWB_SensorUnRegCallBack

all: campipe

campipe: campipe.o $(COMM_OBJ)
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

campipe.o: campipe.c
	$(CC) $(CFLAGS) -c -o $@ $<

# SDK helper objects, compiled from the vendored sample sources.
sample_comm_%.o: $(COMMON)/sample_comm_%.c
	$(CC) $(CFLAGS) -Wno-unused -Wno-unused-but-set-variable -c -o $@ $<

clean:
	rm -f campipe *.o
