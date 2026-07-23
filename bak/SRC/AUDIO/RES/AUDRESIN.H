#ifndef BAK_AUDRESIN_H
#define BAK_AUDRESIN_H

#include "structs.h"

extern unsigned char g_abIntensityCurve[64];
extern unsigned short g_nSfxResourceId;
extern unsigned char far *g_pSsmChunkBuf;
extern AudioListNode far *g_pActiveAudioListHead;
extern unsigned short g_bAudioTimerInstalled;
extern unsigned short g_nSfxSampleSlot;
extern unsigned short g_nSfxWorkSlot;
extern SfxLoopPri *g_pSfxLoopPriorityTable;
extern void far *g_pSfxDriver;
extern void far *g_pMusicDriver;
extern unsigned short g_nAudioBufLastError;
extern unsigned char g_bAudioLooseTag;
extern short g_nAudioFilterMode;
extern MusicChunkHeader far *g_pMusicChunkBuf;
extern BakFile *g_music_archive;
extern int g_music_archive_owned;
extern unsigned short g_bMusicDriverInstalled;
extern unsigned short g_nAudioStreamCodec;

/**
 * @brief Sound-driver ids: indices into the SFX driver-tag table
 *        (@c g_apSfxDriverTags  (TBD-ref: not yet documented)).
 *
 * The id selects the `XXX:` resource tag naming the driver chunk to load
 * from `SX.OVL`. Five ids are selectable via the `sounddrv` config token
 * (@ref g_soundDrvIds); @ref SNDDRV_NONE selects the null driver and is the
 * engine-wide audio-disabled gate. The 1.02 CD build adds @ref SNDDRV_CD.
 */
enum SoundDriverId {
    SNDDRV_STD = 0,  /**< `STD:`; the `std.drv` config token. */
    SNDDRV_TAN = 1,  /**< `TAN:`; no config token. */
    SNDDRV_ADL = 2,  /**< `ADL:` — AdLib FM; the `adl.drv` token. */
    SNDDRV_M32 = 3,  /**< `M32:` — Roland MT-32; the `mt32.drv` token. */
    SNDDRV_SBP = 4,  /**< `SBP:` — Sound Blaster; the `sndblast.drv` token. */
    SNDDRV_PS1 = 5,  /**< `PS1:`; no config token. */
    SNDDRV_PRO = 6,  /**< `PRO:` — Pro Audio; no config token. */
    SNDDRV_GMD = 7,  /**< `GMD:` — General MIDI; the `genmidi.drv` token. */
    SNDDRV_NONE = 8  /**< `NLD:` — the null driver; audio disabled. */
#ifdef V102CD
    ,
    /**
     * @brief 1.02 CD: Red Book CD-audio music mode.
     *
     * Set at boot when a CD is detected and the driver would otherwise be
     * `STD`/`NONE`. Past the end of the 9-entry SFX tag table — CD music
     * routes to the CDAUDIO driver, not to an `SX.OVL` chunk.
     */
    SNDDRV_CD = 9
#endif
};
typedef enum SoundDriverId SoundDriverId;

extern SoundDriverId g_sound_driver;

extern int audio_resource_install_by_id(char *file, int *p_resource_id, int load_mode);

extern char g_szSsmTemplate[9];
extern char g_szSsmTag[9];
extern char *g_apSfxDriverTags[9];
extern char *g_apMusicDriverTags[5];
extern char g_szSfxTag_STD[5];
extern char g_szSfxTag_TAN[5];
extern char g_szSfxTag_ADL[5];
extern char g_szSfxTag_M32[5];
extern char g_szSfxTag_SBP[5];
extern char g_szSfxTag_PS1[5];
extern char g_szSfxTag_PRO[5];
extern char g_szSfxTag_GMD[5];
extern char g_szSfxTag_NLD[5];
extern char g_szMusicTag_ASB[5];
extern char g_szMusicTag_APS[5];
extern char g_szMusicTag_ATD[5];
extern char g_szMusicTag_APA[5];
extern char g_szMusicTag_ADS[5];
extern short g_nSfxDriverMode;

#endif
