#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include "SRC/SYS/PANICF.H"
#include "SRC/SYS/HWSHUT.H"
#include "SRC/GFX/DRIVER/VIDDET.H"

int panic(char *fmt, ...) {
    va_list args;

    hardware_shutdown();
    video_shutdown();
    if (fmt) {
        va_start(args, fmt);
        vprintf(fmt, args);
        printf("\n");
    }
    exit(-1);
    return 0;
}
