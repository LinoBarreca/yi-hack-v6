#!/bin/sh

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

# 6.0.1 - yi-hack-v6
#
# URL helpers for the extra payload. Kept here (not in base/get_config.sh) so the
# scripts that build credentialed URLs - system.sh (ONVIF stream config at boot),
# www/cgi-bin/service.sh (regenerates that config on an RTSP-settings change) and
# record.sh (recorder RTSP URL) - all ship together in `extra` and update over the
# CIFS payload, with no flash of the home partition. Source it after get_config.sh.

# urlencode <string> <outvar> : percent-encode <string> into the variable named
# <outvar>. Credentials embedded in a URL (user:password@) must be encoded: a
# password with URL-reserved characters (@ : ; $ / ? # & ...) would otherwise be
# parsed as delimiters and corrupt the URL - the symptom being an ONVIF client
# (go2rtc, VLC) failing to open the stream. Unreserved chars (RFC 3986:
# A-Z a-z 0-9 - . _ ~) pass through. Fork-free (a builtin char loop: case +
# parameter expansion), so it is safe on the boot/request path; one-shot on short
# strings (user/password), so the loop is cheap.
urlencode() {
    _ue_in=$1
    _ue_out=""
    while [ -n "$_ue_in" ] ; do
        _ue_c=${_ue_in%"${_ue_in#?}"}   # first char
        _ue_in=${_ue_in#?}              # the rest
        case $_ue_c in
            [a-zA-Z0-9.~_-]) _ue_out=$_ue_out$_ue_c ;;
            ' ') _ue_out=$_ue_out%20 ;;  '!') _ue_out=$_ue_out%21 ;;
            '"') _ue_out=$_ue_out%22 ;;  '#') _ue_out=$_ue_out%23 ;;
            '$') _ue_out=$_ue_out%24 ;;  '%') _ue_out=$_ue_out%25 ;;
            '&') _ue_out=$_ue_out%26 ;;  "'") _ue_out=$_ue_out%27 ;;
            '(') _ue_out=$_ue_out%28 ;;  ')') _ue_out=$_ue_out%29 ;;
            '*') _ue_out=$_ue_out%2A ;;  '+') _ue_out=$_ue_out%2B ;;
            ',') _ue_out=$_ue_out%2C ;;  '/') _ue_out=$_ue_out%2F ;;
            ':') _ue_out=$_ue_out%3A ;;  ';') _ue_out=$_ue_out%3B ;;
            '<') _ue_out=$_ue_out%3C ;;  '=') _ue_out=$_ue_out%3D ;;
            '>') _ue_out=$_ue_out%3E ;;  '?') _ue_out=$_ue_out%3F ;;
            '@') _ue_out=$_ue_out%40 ;;  '[') _ue_out=$_ue_out%5B ;;
            '\') _ue_out=$_ue_out%5C ;;  ']') _ue_out=$_ue_out%5D ;;
            '^') _ue_out=$_ue_out%5E ;;  '`') _ue_out=$_ue_out%60 ;;
            '{') _ue_out=$_ue_out%7B ;;  '|') _ue_out=$_ue_out%7C ;;
            '}') _ue_out=$_ue_out%7D ;;
            *) _ue_out=$_ue_out$_ue_c ;;   # rare/non-ASCII: leave as-is
        esac
    done
    eval "$2=\$_ue_out"
}
