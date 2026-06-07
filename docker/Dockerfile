# syntax=docker/dockerfile:1
#
# yi-hack-v6 cross-build environment.
#
# Canonical HiSilicon toolchain `arm-hisiv300-linux` (GCC 4.8.3 Linaro, uClibc 0.9.33.2)
# for the Hi3518Ev200 / ARM926EJ-S cameras (see CAMERA_FIRMWARE_DESIGN.md section 2.1, 6.8).
# Mirror: OpenIPC/toolchains. The toolchain GCC is a 32-bit x86 (i386) binary; the base
# image is amd64. On an aarch64 host both must be emulated via qemu-user — register once:
#   docker run --privileged --rm tonistiigi/binfmt --install amd64,386
#
# Platform is set by `docker build --platform=linux/amd64` (build_all.sh), not hardcoded here.
FROM debian:bookworm-slim

# The HiSilicon toolchain GCC is 32-bit x86 (i386) -> enable i386 multiarch.
# ca-certificates is intentionally omitted: its postinst segfaults under qemu emulation,
# and we don't need TLS validation because the toolchain download is sha256-verified below.
RUN dpkg --add-architecture i386 \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential make cmake autoconf automake libtool pkg-config \
        wget bzip2 xz-utils unzip rsync file git bc python3 \
        libc6:i386 libstdc++6:i386 zlib1g:i386 \
    && rm -rf /var/lib/apt/lists/*

# HiSilicon arm-hisiv300-linux toolchain, pinned + checksum-verified (sha256 is the integrity check).
ARG TC_URL=https://github.com/OpenIPC/toolchains/releases/download/v1/arm-hisiv300-linux.tar.bz2
ARG TC_SHA256=da67276965053ef25940d521f7033a0f2ea7de4f26b6d2b24d4a39e9ba588edf
RUN wget --no-check-certificate -q -O /tmp/tc.tar.bz2 "$TC_URL" \
    && echo "$TC_SHA256  /tmp/tc.tar.bz2" | sha256sum -c - \
    && mkdir -p /opt/hisi-linux/x86-arm \
    && tar xjf /tmp/tc.tar.bz2 -C /opt \
    && ln -sf /opt/arm-hisiv300-linux /opt/hisi-linux/x86-arm/arm-hisiv300-linux \
    && rm /tmp/tc.tar.bz2

# Both path conventions used by the build scripts:
#   compile.* / compile.sh  -> /opt/arm-hisiv300-linux/bin
#   config.mak              -> /opt/hisi-linux/x86-arm/arm-hisiv300-linux/target/usr/{include,lib}
ENV PATH=/opt/arm-hisiv300-linux/bin:$PATH

WORKDIR /work
