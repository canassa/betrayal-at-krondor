#include "globals.h"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/STREAM/BUFLOAD/LOADCHNK.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"
#include "SRC/AUDIO/RES/PASCREC.H"

char g_szSsmTemplate[9] = "SSM:000:";

unsigned char _dgroup_pad_351b[1] = {0x00};
unsigned char g_abIntensityCurve[64] = {
    0x00, 0x05, 0x0a, 0x0d, 0x10, 0x13, 0x16, 0x19, 0x1c, 0x1f, 0x22, 0x25, 0x28, 0x2b, 0x2e, 0x2f,
    0x32, 0x35, 0x38, 0x3b, 0x3d, 0x3f, 0x41, 0x43, 0x44, 0x46, 0x48, 0x4a, 0x4c, 0x4e, 0x50, 0x52,
    0x54, 0x56, 0x58, 0x5a, 0x5c, 0x5e, 0x62, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c,
    0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7d};

unsigned char _dgroup_intensity_curve65_pad[2] = {0x7f, 0x00};
char g_szSsmTag[9] = "SSM:     ";

unsigned char _dgroup_pad_3567[1] = {0x00};
char *g_apSfxDriverTags[9] = {
    (char *)g_szSfxTag_STD, (char *)g_szSfxTag_TAN, (char *)g_szSfxTag_ADL,
    (char *)g_szSfxTag_M32, (char *)g_szSfxTag_SBP, (char *)g_szSfxTag_PS1,
    (char *)g_szSfxTag_PRO, (char *)g_szSfxTag_GMD, (char *)g_szSfxTag_NLD};
char *g_apMusicDriverTags[5] = {(char *)g_szMusicTag_ASB, (char *)g_szMusicTag_APS,
                                (char *)g_szMusicTag_ATD, (char *)g_szMusicTag_APA,
                                (char *)g_szMusicTag_ADS};
char g_szSfxTag_STD[5] = "STD:";
char g_szSfxTag_TAN[5] = "TAN:";
char g_szSfxTag_ADL[5] = "ADL:";
char g_szSfxTag_M32[5] = "M32:";
char g_szSfxTag_SBP[5] = "SBP:";
char g_szSfxTag_PS1[5] = "PS1:";
char g_szSfxTag_PRO[5] = "PRO:";
char g_szSfxTag_GMD[5] = "GMD:";
char g_szSfxTag_NLD[5] = "NLD:";
char g_szMusicTag_ASB[5] = "ASB:";
char g_szMusicTag_APS[5] = "APS:";
char g_szMusicTag_ATD[5] = "ATD:";
char g_szMusicTag_APA[5] = "APA:";
char g_szMusicTag_ADS[5] = "ADS:";
unsigned short g_nSfxResourceId = 0x0000;
unsigned char far *g_pSsmChunkBuf = {0};
AudioListNode far *g_pActiveAudioListHead = {0};
unsigned short g_bAudioTimerInstalled = 0x0000;
unsigned short g_nSfxSampleSlot = 0x0000;
unsigned short g_nSfxWorkSlot = 0x0000;
SfxLoopPri *g_pSfxLoopPriorityTable = {0};
void far *g_pSfxDriver = {0};
void far *g_pMusicDriver = {0};
unsigned short g_nAudioBufLastError = 0x0000;
unsigned char g_bAudioLooseTag = 0x00;

unsigned char _dgroup_pad_35e7[1] = {0x00};
short g_nAudioFilterMode = -4;
MusicChunkHeader far *g_pMusicChunkBuf = {0};
BakFile *g_music_archive = {0};
int g_music_archive_owned = 0;
unsigned short g_bMusicDriverInstalled = 0x0000;
unsigned short g_nAudioStreamCodec = 0x0001;
short g_nSfxDriverMode = -2;

short g_nAudioDefaultSfxMode = -2;
unsigned short g_nAudioDefaultSampleRate = 11025;

int audio_resource_install_by_id(char *file, int *p_resource_id, int load_mode) {
    char *id;
    int result;

    result = 1;
    if (*p_resource_id != 0xff) {
        id = g_szSsmTemplate;
        g_szSsmTemplate[4] = *p_resource_id / 100 + '0';
        g_szSsmTemplate[5] = *p_resource_id / 10 % 10 + '0';
        g_szSsmTemplate[6] = *p_resource_id % 10 + '0';
        if (g_pSsmChunkBuf != 0) {
            release_buffer(g_pSsmChunkBuf, 1);
        }
        if ((g_pSsmChunkBuf = bak_load_chunk(file, id, load_mode)) == 0) {
            result = 0;
        }
    }
    if (result != 0) {
        if (midi_cmd1_save_cx_303b4_thunk(advance_pascal_record(g_pSsmChunkBuf)) == 0xffff) {
            result = 0;
        }
    }
    if (g_pSsmChunkBuf != 0) {
        release_buffer(g_pSsmChunkBuf, 1);
        g_pSsmChunkBuf = 0;
    }
    return result;
}
