#!/bin/sh

# This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
# Copyright (c) 2021 alienatedsec
# Copyright (c) 2026 Lino Barreca.

set -e

git config -f .gitmodules --get-regexp '^submodule\..*\.path$' |
    while read path_key path
    do
        url_key=$(echo $path_key | sed 's/\.path/.url/')
        url=$(git config -f .gitmodules --get "$url_key")
        git submodule add --force $url $path
    done
