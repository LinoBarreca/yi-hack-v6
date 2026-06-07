
CC=arm-hisiv300-linux-uclibcgnueabi-gcc
USER_CFLAGS=-march=armv5te -mcpu=arm926ej-s -I/opt/arm-hisiv300-linux/target/usr/include -L/opt/arm-hisiv300-linux/target/usr/lib
prefix=/tmp/sd/yi-hack
exec_prefix=/tmp/sd/yi-hack
bindir=/tmp/sd/yi-hack/bin
libdir=/tmp/sd/yi-hack/lib
includedir=/include
sysconfdir=/tmp/sd/yi-hack/etc
CPPFLAGS+= -DSUPER_SECURE
CPPFLAGS+=  -Wno-unknown-pragmas -DGN_NODELEN_T=socklen_t -DGN_SERVLEN_T=socklen_t -DGN_FLAGS_T=unsigned -DHAVE_GNU_GETSERVBYNAME_R -DHAVE_PIPE2 -DHAVE_SOCK_CLOEXEC -DHAVE_CLOCK_GETTIME
LD_SET_SONAME = -Wl,--soname,
LIBDL = -ldl
PTHREAD = -lpthread
