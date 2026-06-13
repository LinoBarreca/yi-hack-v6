#!/usr/bin/env python3
"""Minimal legacy U-Boot uImage generator (dependency-free mkimage replacement).

Produces the same 64-byte legacy uImage header that
`mkimage -A <arch> -T <type> -C <comp> -n <name> -d <in> <out>` produces, so the
HiSilicon U-Boot `do_auto_sd_update` routine accepts the rootfs_<model>/home_<model>
files (it validates magic + header CRC + data CRC). We use this instead of mkimage
because mkimage links libcrypto.so.3, which fails to load under qemu-user on a
16K-page aarch64 host (same limit that breaks rsync — see design §6.8).

The legacy header is fully specified (no crypto): magic, two CRC32s (IEEE, zlib),
and big-endian fields. See U-Boot include/image.h.
"""
import argparse
import struct
import sys
import time
import zlib

MAGIC = 0x27051956

ARCH = {"invalid": 0, "arm": 2, "x86": 3, "mips": 5}
OS = {"invalid": 0, "linux": 5, "u-boot": 17}
TYPE = {
    "standalone": 1, "kernel": 2, "ramdisk": 3, "multi": 4,
    "firmware": 5, "script": 6, "filesystem": 7, "flat_dt": 8,
}
COMP = {"none": 0, "gzip": 1, "bzip2": 2, "lzma": 3}


def build(data, arch, os_, type_, comp, name, ts):
    name_b = name.encode()[:31].ljust(32, b"\0")
    dcrc = zlib.crc32(data) & 0xFFFFFFFF
    # header with hcrc=0, compute hcrc, then rewrite
    hdr = struct.pack(
        ">IIIIIII4B32s",
        MAGIC, 0, ts, len(data), 0, 0, dcrc,
        os_, arch, type_, comp, name_b,
    )
    hcrc = zlib.crc32(hdr) & 0xFFFFFFFF
    hdr = struct.pack(
        ">IIIIIII4B32s",
        MAGIC, hcrc, ts, len(data), 0, 0, dcrc,
        os_, arch, type_, comp, name_b,
    )
    return hdr + data


def main():
    p = argparse.ArgumentParser()
    p.add_argument("-A", dest="arch", default="arm")
    p.add_argument("-O", dest="os", default="linux")
    p.add_argument("-T", dest="type", default="filesystem")
    p.add_argument("-C", dest="comp", default="none")
    p.add_argument("-n", dest="name", default="")
    p.add_argument("-d", dest="data", required=True)
    p.add_argument("output")
    a = p.parse_args()

    try:
        arch, os_, type_, comp = ARCH[a.arch], OS[a.os], TYPE[a.type], COMP[a.comp]
    except KeyError as e:
        sys.exit(f"mkuimage: unknown value {e}")

    with open(a.data, "rb") as f:
        data = f.read()
    img = build(data, arch, os_, type_, comp, a.name, int(time.time()))
    with open(a.output, "wb") as f:
        f.write(img)


if __name__ == "__main__":
    main()
