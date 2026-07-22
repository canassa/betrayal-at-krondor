#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "globals.h"
#include "structs.h"
#include "SRC/GAME/CFGPARSE.H"

char *g_apSoundDriverNames[5] = {(char *)g_szDrvAdl, (char *)g_szDrvMt32, (char *)g_szDrvSndblast,
                                 (char *)g_szDrvStd, (char *)g_szDrvGenmidi};
unsigned short g_awSoundDriverCodes[5] = {0x0002, 0x0003, 0x0004, 0x0000, 0x0007};
/**
 * @brief Cheat-menu unlock flag, read by the 3-D world view.
 *
 * FALSE on a stock install; set TRUE only when @c resource.cfg carries a
 * @c knockknock line whose argument is exactly 29 characters. While TRUE,
 * the RShift+Alt+tilde chord opens the hidden cheat menu.
 */
bool16 g_knockKnock = FALSE;
unsigned short g_cycle = 0x0000;
int g_temp_drive = 0x0000;
bool16 g_bookmark_verify = TRUE;
char g_szDrvAdl[8] = "adl.drv";
char g_szDrvMt32[9] = "mt32.drv";
char g_szDrvSndblast[13] = "sndblast.drv";
char g_szDrvStd[8] = "std.drv";
char g_szDrvGenmidi[12] = "genmidi.drv";

void parse_krondor_cfg(void) {
    char token[40];
    int done;
    register FILE *fp;
    int i;

    done = 0;
    fp = fopen("resource.cfg", "rb");
    while (!done) {
        if (fscanf(fp, " %40s", token) == EOF) {
            done = 1;
            continue;
        }
        if (stricmp("sounddrv", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            for (i = 0; i < 5; i++) {
                if (stricmp(g_apSoundDriverNames[i], token) == 0) {
                    g_sound_driver = g_awSoundDriverCodes[i];
                    break;
                }
            }
        } else if (stricmp("knockknock", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            if (strlen(token) == 29)
                g_knockKnock = TRUE;
        } else if (stricmp("cycle", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            g_cycle = atoi(token);
        } else if (stricmp("tempdrive", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            if (isalpha(token[0]))
                g_temp_drive = toupper(token[0]);
        } else if (stricmp("bookmarkverify", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            g_bookmark_verify = atoi(token);
        }
    }
}
