/*
 * This file is part of yi-hack-v6 (https://github.com/LinoBarreca/yi-hack-v6).
 * Copyright (c) 2026 Lino Barreca.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

/* Toolchain smoke-test for yi-hack-v6 (build_all.sh hello). */
#include <stdio.h>
#include <sys/utsname.h>

int main(void) {
    struct utsname u;
    printf("hello from arm-hisiv300 / uClibc 0.9.33.2\n");
    if (uname(&u) == 0)
        printf("uname: %s %s %s\n", u.sysname, u.release, u.machine);
    return 0;
}
