#!/bin/bash

#
#  This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
#  Copyright (c) 2021-2023 alienatedsec - v5 specific
#  Copyright (c) 2026 Lino Barreca.
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, version 3.
#
#  This program is distributed in the hope that it will be useful, but
#  WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
#  General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program. If not, see <http://www.gnu.org/licenses/>.
#

# jq 1.8.2 (jqlang). Upgraded from 1.6: the old release recompiled its ~1700-line
# builtin library on every startup (accidentally quadratic - ~10-12 s per run on
# this SoC). 1.7 fixed that; 1.8.2 is the current stable. Regex (oniguruma) and
# decNumber ship bundled under vendor/ and are built in-tree, so no system libs are
# needed on the ancient arm-hisiv300 / uClibc toolchain. Parser and lexer are
# pre-generated in the tarball, so no bison/flex is required either.

VERSION=1.8.2
ARCHIVE=jq-${VERSION}.tar.gz
URL=https://github.com/jqlang/jq/releases/download/jq-${VERSION}/${ARCHIVE}
SHA256=71b8d6e8f5fe81f6c6d0d110e3892251f6ce76ed095abd315e26e6e1193af3af

SCRIPT_DIR=$(cd `dirname $0` && pwd)
cd $SCRIPT_DIR

rm -rf ./_install
rm -rf ./jq-${VERSION}

if [ ! -f $ARCHIVE ]; then
    wget -O $ARCHIVE $URL || wget --no-check-certificate -O $ARCHIVE $URL || exit 1
fi

# Integrity is guaranteed by the pinned sha256 (so --no-check-certificate above is safe).
echo "${SHA256}  ${ARCHIVE}" | sha256sum -c - || { echo "jq: sha256 mismatch on $ARCHIVE"; exit 1; }

tar zxf $ARCHIVE || exit 1

cd jq-${VERSION} || exit 1

# Release tarball is already ./configure-ready (no autoreconf needed).
#   --with-oniguruma=builtin : build the bundled regex lib in-tree (match/test/sub)
#   --disable-shared --enable-static : fold libjq into a single standalone binary
#      (jq links it statically; libc/libpthread stay dynamic, resolved from /home/lib
#      via the firmware's LD_LIBRARY_PATH, exactly like every other yi-hack binary.
#      1.8.x needs libpthread for decNumber/dtoa thread-local state; 1.6 did not.)
#   --disable-docs : no python/mkdocs in the build image
./configure \
    CC=arm-hisiv300-linux-uclibcgnueabi-gcc \
    AR=arm-hisiv300-linux-uclibcgnueabi-ar \
    RANLIB=arm-hisiv300-linux-uclibcgnueabi-ranlib \
    CFLAGS="-march=armv5te -mcpu=arm926ej-s -O2" \
    --host=arm-hisiv300-linux-uclibcgnueabi \
    --with-oniguruma=builtin \
    --disable-shared --enable-static \
    --disable-docs \
    --disable-maintainer-mode \
    --prefix=$SCRIPT_DIR/_install || exit 1
