# syntax=docker/dockerfile:1
#
# yi-hack-v6 cross-build environment.
#
# Canonical HiSilicon toolchain `arm-hisiv300-linux` (GCC 4.8.3 Linaro, uClibc 0.9.33.2)
# for the Hi3518Ev200 / ARM926EJ-S cameras (ARMv5TE, kernel 3.4.35). Mirror: OpenIPC/toolchains. The toolchain GCC is a 32-bit x86 (i386) binary; the base
# image is amd64. On an aarch64 host both must be emulated via qemu-user — register once:
#   docker run --privileged --rm tonistiigi/binfmt --install amd64,386
#
# Platform is set by `docker build --platform=linux/amd64` (build_all.sh), not hardcoded here.
FROM debian:bookworm-slim

# The HiSilicon toolchain GCC is 32-bit x86 (i386) -> enable i386 multiarch.
# ca-certificates cannot be *installed* normally here: its postinst (update-ca-certificates)
# segfaults under qemu emulation. So we fetch the .deb and extract the CA bundle by hand
# (no postinst) -> wget/git get working TLS for the module source downloads (busybox, jq,
# curl, wpa, onvif, rRTSPServer all wget their tarballs over https).
RUN dpkg --add-architecture i386 \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential make cmake autoconf automake libtool pkg-config \
        wget bzip2 xz-utils unzip rsync file git bc python3 meson ninja-build \
        libxml2-utils \
        libc6:i386 libstdc++6:i386 zlib1g:i386 \
    && apt-get download ca-certificates \
    && dpkg-deb -x ca-certificates_*.deb /tmp/cacerts \
    && mkdir -p /etc/ssl/certs \
    && cat /tmp/cacerts/usr/share/ca-certificates/mozilla/*.crt > /etc/ssl/certs/ca-certificates.crt \
    && rm -rf ca-certificates_*.deb /tmp/cacerts /var/lib/apt/lists/*

# HiSilicon arm-hisiv300-linux toolchain, pinned + checksum-verified (sha256 is the integrity check).
ARG TC_URL=https://github.com/OpenIPC/toolchains/releases/download/v1/arm-hisiv300-linux.tar.bz2
ARG TC_SHA256=da67276965053ef25940d521f7033a0f2ea7de4f26b6d2b24d4a39e9ba588edf
RUN wget --no-check-certificate -q -O /tmp/tc.tar.bz2 "$TC_URL" \
    && echo "$TC_SHA256  /tmp/tc.tar.bz2" | sha256sum -c - \
    && mkdir -p /opt/hisi-linux/x86-arm \
    && tar xjf /tmp/tc.tar.bz2 -C /opt \
    && ln -sf /opt/arm-hisiv300-linux /opt/hisi-linux/x86-arm/arm-hisiv300-linux \
    && rm /tmp/tc.tar.bz2

# Some v5 build scripts (curl's openssl, wpa) call the toolchain by its SHORT prefix
# `arm-hisiv300-linux-*`; this OpenIPC toolchain names the tools with the full triplet
# `arm-hisiv300-linux-uclibcgnueabi-*`. Provide short-prefix symlinks for compatibility.
RUN cd /opt/arm-hisiv300-linux/bin \
    && for t in arm-hisiv300-linux-uclibcgnueabi-*; do \
         ln -sf "$t" "arm-hisiv300-linux-${t#arm-hisiv300-linux-uclibcgnueabi-}"; \
       done

# Both path conventions used by the build scripts:
#   compile.* / compile.sh  -> /opt/arm-hisiv300-linux/bin
#   config.mak              -> /opt/hisi-linux/x86-arm/arm-hisiv300-linux/target/usr/{include,lib}
ENV PATH=/opt/arm-hisiv300-linux/bin:$PATH

WORKDIR /work
