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
