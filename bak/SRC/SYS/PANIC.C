#include <stdio.h>
#include "globals.h"
#include "structs.h"
#include "SRC/SYS/PANIC.H"
#include "SRC/SYS/HWSHUT.H"
#include "SRC/GFX/DRIVER/VIDDET.H"
#include "SRC/GAME/BOOT.H"

int panic_fatal_error_exit(char far *module, int line, char *msg) {
    video_shutdown();
    if (module != 0) {
        printf("A system error has occured.  Please write down the\n");
        printf("following data and contact Sierra Customer Support:\n");
        printf("%Fs:%d (%s)\n", module, line, msg != 0 ? msg : " ");
    }
    boot_engine_exit(0);
}

void far panic_assert_fail_report(char far *file, int line) {
    video_shutdown();
    printf("Bad Midkemian!\n");
    printf("FILE = %Fs\n", file);
    printf("LINE = %d\n", line);
    hardware_shutdown();
    boot_engine_exit(0);
}
