#!/bin/bash

#
#  This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
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

#
# fetch_www_vendor.sh - download the third-party libraries used by the full web
# UI into src/www/httpd/htdocs/vendor/ and verify their sha256 checksums.
#
# Like every other module source in this project, the files are NOT committed
# to git: they are fetched at build time (compile.www calls this script when
# the cached copies are missing or fail verification) and cached in the vendor
# dir, so normal rebuilds stay offline. Integrity comes from the PINNED sha256
# below (same pattern as the toolchain download); this is also the one place
# to bump versions (update VERSION + SHA256, delete the cached files, rebuild).
#
# Usage: scripts/fetch_www_vendor.sh [--verify-only]

set -euo pipefail

VENDOR_DIR="$(cd "$(dirname "$0")/.." && pwd)/src/www/httpd/htdocs/vendor"

BOOTSTRAP_VERSION=5.3.8
ALPINE_VERSION=3.15.0

# file|url|sha256  (sha256 of the upstream release artifact)
MANIFEST=(
"bootstrap.min.css|https://cdn.jsdelivr.net/npm/bootstrap@${BOOTSTRAP_VERSION}/dist/css/bootstrap.min.css|d85327d99c7a3ee1f9b5d0500d1370acea3ad2db39c163c2f51f232baedbdede"
"bootstrap.bundle.min.js|https://cdn.jsdelivr.net/npm/bootstrap@${BOOTSTRAP_VERSION}/dist/js/bootstrap.bundle.min.js|e4fd49181388c48ec5040bd3fe66f57c29c8e67fcd8502b3354b96ec7ab47cc7"
"alpine.min.js|https://cdn.jsdelivr.net/npm/alpinejs@${ALPINE_VERSION}/dist/cdn.min.js|e041f1b639d1e6b2fc2736d8d7638a409afcd444a6ec90446f8f4e44fa36f406"
)

mkdir -p "$VENDOR_DIR"
rc=0
for entry in "${MANIFEST[@]}"; do
    IFS='|' read -r file url sha <<< "$entry"
    dest="$VENDOR_DIR/$file"
    if [ "${1:-}" != "--verify-only" ]; then
        echo "fetching $file  <-  $url"
        # TLS fallback mirrors the toolchain download (qemu container quirks):
        # integrity is guaranteed by the pinned sha256 below, not by the cert.
        wget -q "$url" -O "$dest" || wget -q --no-check-certificate "$url" -O "$dest"
    fi
    have=$(sha256sum "$dest" | cut -d' ' -f1)
    if [ "$have" = "$sha" ]; then
        echo "OK       $file  $have"
    else
        echo "MISMATCH $file  have $have  want $sha" >&2
        rc=1
    fi
done
exit $rc
