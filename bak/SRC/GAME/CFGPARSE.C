/**
 * @file  CFGPARSE.C
 * @brief `resource.cfg` parser and the `g_cfg` settings globals it fills;
 *        the 1.02 CD build also reads the installer-written `drive.cfg` here.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "SRC/GAME/CFGPARSE.H"
#include "SRC/AUDIO/RES/AUDRESIN.H"


/**
 * @brief Tokens accepted as the `sounddrv` argument in `resource.cfg`.
 *
 * Matched case-insensitively against the key's argument. Despite the `.drv`
 * spelling these are plain config tokens, not filenames — nothing is opened
 * by these names. A match selects the entry at the same index of
 * @ref g_soundDrvIds.
 */
char *g_soundDrvTokens[5] = {"adl.drv", "mt32.drv", "sndblast.drv", "std.drv", "genmidi.drv"};


/**
 * @brief Driver ids parallel to @ref g_soundDrvTokens.
 *
 * The entry at the matched token's index becomes the active sound driver:
 * an id indexing the SX.OVL driver-tag table, not a file or an OS driver.
 */
SoundDriverId g_soundDrvIds[5] = {SNDDRV_ADL, SNDDRV_M32, SNDDRV_SBP, SNDDRV_STD, SNDDRV_GMD};


#ifdef V102CD
char *g_cfgResourceDrivePrefix = "x:";
char g_cfgCdDriveLetter = 'x';
#endif
bool16 g_cfgKnockKnock = FALSE;
int g_cfgCycle = 0;
int g_cfgTempDrive = 0;
bool16 g_cfgBookmarkVerify = TRUE;
#ifdef V102CD
bool16 g_cfgNonRotatingMap = FALSE;
#endif


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
#ifdef V102CD
        } else if (stricmp("NonRotatingMap", token) == 0) {
            fscanf(fp, " %40s", token);
            fscanf(fp, " %40s", token);
            g_cfgNonRotatingMap = atoi(token);
#endif
        }
    }
#ifdef V102CD
    fclose(fp);
    fp = fopen("drive.cfg", "rb");
    fscanf(fp, "%40s", token);
    *g_cfgResourceDrivePrefix = token[0];
    fscanf(fp, "%40s", token);
    g_cfgCdDriveLetter = token[0];
    fclose(fp);
#endif
}
