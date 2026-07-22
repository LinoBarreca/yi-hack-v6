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

# lint_shell_hotpaths.sh - grep gate against fork-per-token shell anti-patterns
# in the shipped scripts. On the camera CPU (ARM926 ~400MHz) every fork or
# subshell costs ~50-70ms, so an `echo|cut` parse loop or one $(get_config)
# per key turns a 40ms request into a multi-second one. Use instead (see
# src/static/static/home/yi-hack/base/script/get_config.sh):
#   - IFS + ${var%%=*} / ${var#*=} parameter expansion for parsing
#   - `read VAR < file` for single-line files
#   - `load_config <file> KEY...` for config values (fork-free batch reader)
# Run from anywhere; exits nonzero when a pattern is found.

set -u
cd "$(dirname "$0")/.." || exit 1

RC=0
report() {   # report <label> <matches>
    [ -z "$2" ] && return 0
    echo "FAIL: $1"
    echo "$2" | sed 's/^/  /'
    echo
    RC=1
}

# scan <grep args...> - grep exits 1 for "no match" (the good case) but 2 for a
# real error: bad option, unreadable path. Never send that to /dev/null - a
# silently failing grep makes the whole gate pass vacuously (green CI, zero
# checks run). grep's own stderr stays visible, and rc>1 is injected into the
# result so report() turns it into a lint failure. scan runs inside $( ), so it
# cannot set RC itself - the caller's subshell would swallow it.
scan() {
    _out="$(grep "$@")"; _rc=$?
    [ $_rc -gt 1 ] && _out="${_out}${_out:+
}GREP FAILED (rc=$_rc), pattern not checked: grep $*"
    [ -n "$_out" ] && printf '%s\n' "$_out"
    return 0
}

CGI_DIRS="src/www/httpd/cgi-bin src/static/static/home/yi-hack/base/www-min/cgi-bin"
SHIPPED_DIRS="src/static src/www"
for _d in $CGI_DIRS $SHIPPED_DIRS; do
    [ -d "$_d" ] || { echo "ERROR: missing scan dir $_d (renamed? fix this script)" >&2; exit 2; }
done

# 1) echo|cut token parsing - anywhere in shipped shell (single-pipe form;
#    legitimate hash pipelines like `echo | md5sum | cut` do not match).
report 'echo|cut parsing (use IFS + ${var%%=*} / ${var#*=})' \
    "$( scan -rnE 'echo [^|]*\|[[:space:]]*cut' --include='*.sh' --exclude-dir=_install src/
        scan -nE  'echo [^|]*\|[[:space:]]*cut' src/www/httpd/cgi-bin/status.json )"

# 2) cat-in-substitution anywhere in the shipped tree - use `read VAR < file`.
#    Not just the CGIs: /etc/profile runs on every login shell and the init
#    scripts run on every boot, which is the same fork tax on the same CPU.
report 'cat in command substitution (use read VAR < file)' \
    "$(scan -rnI -E '\$\(cat |`cat ' --exclude-dir=_install $SHIPPED_DIRS)"

# 3) get_config-in-substitution in CGIs - use load_config.
report 'get_config in command substitution in CGIs (use load_config)' \
    "$(scan -rnE '\$\(get_config|`get_config' $CGI_DIRS)"

# 4) dd with its stderr suppressed and no check on the result.
#
#    dd is the one command that legitimately NEEDS 2>/dev/null - it reports
#    transfer stats on stderr, which would corrupt a captured value. But the
#    same redirect hides a real failure (missing file, short read, an option
#    this busybox build does not accept), and an unchecked dd then hands back
#    an empty string that reads as valid data. Every such site must either
#    check the status on the same line (`|| ...`) or carry a `# dd-checked`
#    comment explaining how the caller validates the value.
report 'dd with suppressed stderr and unchecked result (add `|| ...` or `# dd-checked`)' \
    "$(scan -rnI -E 'dd [^|]*2>/dev/null' --exclude-dir=_install $SHIPPED_DIRS \
       | grep -v -e '||' -e 'dd-checked')"

[ $RC -eq 0 ] && echo "shell hot-path lint: OK"
exit $RC
