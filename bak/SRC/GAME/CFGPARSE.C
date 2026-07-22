#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "globals.h"
#include "structs.h"
#include "SRC/GAME/CFGPARSE.H"
#include "SRC/AUDIO/RES/AUDRESIN.H"

char *g_soundDrvTokens[5] = {"adl.drv", "mt32.drv", "sndblast.drv", "std.drv", "genmidi.drv"};
unsigned short g_soundDrvIds[5] = {SNDDRV_ADL, SNDDRV_M32, SNDDRV_SBP, SNDDRV_STD, SNDDRV_GMD};
/**
 * @brief Cheat-menu unlock flag, read by the 3-D world view.
 *
 * FALSE on a stock install; set TRUE only when `resource.cfg` carries a
 * `knockknock` line whose argument is exactly 29 characters. While TRUE,
 * the RShift+Alt+tilde chord opens the hidden cheat menu.
 */
bool16 g_cfgKnockKnock = FALSE;
/**
 * @brief Value of the undocumented `cycle` config key — dead, never read.
 *
 * Parsed from a `cycle` line in `resource.cfg` into this global, which has no
 * reader anywhere in the game.
 */
unsigned short g_cfgCycle = 0x0000;
/**
 * @brief Drive letter for the `TEMP.GAM` swap file (0 = current drive).
 *
 * Set from the `tempdrive` line in `resource.cfg` (its first character,
 * upper-cased). When non-zero the swap path is drive-relative `D:TEMP.GAM`;
 * when 0 (the default) the file is the bare `TEMP.GAM` on the current drive.
 */
int g_cfgTempDrive = 0x0000;
/**
 * @brief Bookmark-overwrite confirmation flag.
 *
 * TRUE by default; set from the `bookmarkverify` line in `resource.cfg`.
 * While TRUE, saving a bookmark first prompts to confirm before it
 * overwrites the existing one; while FALSE the save is silent.
 */
bool16 g_cfgBookmarkVerify = TRUE;

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
                if (stricmp(g_soundDrvTokens[i], token) == 0) {
                    g_sound_driver = g_soundDrvIds[i];
                    break;
                }
            }
        } else if (stricmp("knockknock", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            if (strlen(token) == 29)
                g_cfgKnockKnock = TRUE;
        } else if (stricmp("cycle", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            g_cfgCycle = atoi(token);
        } else if (stricmp("tempdrive", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            if (isalpha(token[0]))
                g_cfgTempDrive = toupper(token[0]);
        } else if (stricmp("bookmarkverify", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            g_cfgBookmarkVerify = atoi(token);
        }
    }
}
