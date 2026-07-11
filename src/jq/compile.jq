#!/bin/bash

export PATH=${PATH}:/opt/arm-hisiv300-linux/bin

export CROSS=arm-hisiv300-linux-uclibcgnueabi
export CROSSPREFIX=${CROSS}-
export STRIP=${CROSSPREFIX}strip

VERSION=1.8.2

SCRIPT_DIR=$(cd `dirname $0` && pwd)
cd $SCRIPT_DIR

# init.jq already ran ./configure (which recursed into vendor/oniguruma and
# vendor/decNumber via AC_CONFIG_SUBDIRS). Just build.
cd jq-${VERSION} || exit 1

make || exit 1

mkdir -p ../_install/bin || exit 1

cp ./jq ../_install/bin || exit 1

${STRIP} ../_install/bin/* || exit 1
