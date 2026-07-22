/**
 * @file  structs.h
 * @brief Engine-wide struct, enum, and typedef definitions.
 */
#ifndef BAK_STRUCTS_H
#define BAK_STRUCTS_H
#include "gtypes.h"
#include <stdio.h>

enum CreatureType {
    CREATURE_GORATH = 15,
    CREATURE_OWYN = 16,
    CREATURE_LOCKLEAR = 17,
    CREATURE_MOREDHEL_WARRIOR = 18,
    CREATURE_BRAK_NURR = 19,
    CREATURE_MOREDHEL_SPELLCASTER = 21,
    CREATURE_BLACK_SLAYER = 22,
    CREATURE_NIGHTHAWK = 23,
    CREATURE_ROGUE = 24,
    CREATURE_PANTATHIAN = 25,
    CREATURE_PANTH_TIANDN = 26,
    CREATURE_SPELLWEAVER = 27,
    CREATURE_SERVITOR_OF_LIMS_KRAGMA = 28,
    CREATURE_TOR_GIANT = 29,
    CREATURE_ROGUE_MAGE = 30,
    CREATURE_DEEP_GIANT = 31,
    CREATURE_CAVE_GIANT = 32,
    CREATURE_RIME_GIANT = 33,
    CREATURE_SENTINEL_OGRE = 34,
    CREATURE_HIGHLAND_OGRE = 37,
    CREATURE_SCORPION = 39,
    CREATURE_BULLDRAKE_WYVERN = 41,
    CREATURE_GRANDSIRE_WYVERN = 42,
    CREATURE_HATCHLING_WYVERN = 43,
    CREATURE_SPIDER = 44,
    CREATURE_PUG = 45,
    CREATURE_BEASTHOUND = 46,
    CREATURE_PATRUS = 47,
    CREATURE_TROLL = 48,
    CREATURE_DREAD = 49,
    CREATURE_JAMES = 51,
    CREATURE_WITCH_HAG = 52,
    CREATURE_GOBLIN = 53,
    CREATURE_WIND_ELEMENTAL = 54,
    CREATURE_QUEGIAN_PIRATE = 55,
    CREATURE_RUSALKI = 56,
    CREATURE_SHADE = 57,
    CREATURE_NETHERMANDER = 58,
    CREATURE_GREAT_ONE = 61,
};
typedef enum CreatureType CreatureType;
enum ScreenHeightPx {
    SCREEN_H_VGA = 200,
    SCREEN_H_NEW = 320,
};
typedef enum ScreenHeightPx ScreenHeightPx;
enum ScreenWidthPx {
    SCREEN_W_VGA = 320,
    SCREEN_W_NEW = 640,
};
typedef enum ScreenWidthPx ScreenWidthPx;
enum SkillType {
    SKILL_HEALTH = 0,
    SKILL_STAMINA = 1,
    SKILL_SPEED = 2,
    SKILL_STRENGTH = 3,
    SKILL_DEFENSE = 4,
    SKILL_CROSSBOW = 5,
    SKILL_MELEE = 6,
    SKILL_CASTING = 7,
    SKILL_ASSESSMENT = 8,
    SKILL_ARMORCRAFT = 9,
    SKILL_WEAPONCRAFT = 10,
    SKILL_BARDING = 11,
    SKILL_HAGGLING = 12,
    SKILL_LOCKPICK = 13,
    SKILL_SCOUTING = 14,
    SKILL_STEALTH = 15,
};
typedef enum SkillType SkillType;
enum VideoMode {
    VIDEO_MODE_CGA = 1,
    VIDEO_MODE_EGA = 2,
    VIDEO_MODE_TAN = 3,
    VIDEO_MODE_HER = 4,
    VIDEO_MODE_MCG = 5,
    VIDEO_MODE_BAD = 6,
    VIDEO_MODE_EVA = 7,
    VIDEO_MODE_VGA = 8,
    VIDEO_MODE_EVG = 9,
    VIDEO_MODE_HVG = 10,
    VIDEO_MODE_HEG = 11,
    VIDEO_MODE_NEW = 12,
};
typedef enum VideoMode VideoMode;

typedef void *__gnuc_va_list;
typedef unsigned int __mode_t;
typedef int __ssize_t;
typedef unsigned short CombatResCacheCol[8][3];
typedef int intptr_t;
#ifndef _SIZE_T
#define _SIZE_T
typedef unsigned short size_t;
#endif
typedef __ssize_t ssize_t;

typedef struct ActSpriteCache ActSpriteCache;
typedef struct Rect Rect;
typedef struct ViewContext ViewContext;
typedef struct ActorStatModifier ActorStatModifier;
typedef struct AnimSlot AnimSlot;
typedef struct AudFragNode AudFragNode;
typedef struct AudioListNode AudioListNode;
typedef struct AudioTrackHandle AudioTrackHandle;
typedef struct BakArchive BakArchive;
typedef struct BakArchiveTable BakArchiveTable;
/**
 * @brief Opaque file token from bak_fopen()/cached_file_open().
 *
 * Really a CRT `FILE *` or a ::BakHandle pool slot; bak_find_handle() tells
 * them apart on every bak_* call. Store it, compare it, pass it back — never
 * dereference it or hand it to CRT stdio. Intentionally has no definition.
 */
typedef struct BakFile BakFile;
/**
 * @brief A file reference: either a filename (`char *`) or an open ::BakFile token.
 *
 * is_file_cached() tells the two apart at runtime by pointer identity. Plain void
 * underneath, so both kinds pass without casts.
 */
typedef void BakFileRef;
typedef struct BakHandle BakHandle;
typedef struct BakIndexEntry BakIndexEntry;
typedef struct BmxHeader BmxHeader;
typedef struct BookImage BookImage;
typedef struct BookPage BookPage;
typedef struct BookViewerState BookViewerState;
typedef struct BorlandFarPtr BorlandFarPtr;
typedef struct WorldPos WorldPos;
typedef struct CircObj CircObj;
typedef struct SpriteBillboard SpriteBillboard;
typedef struct CodecVtable CodecVtable;
typedef struct CombatActor CombatActor;
typedef struct CombatActorInner CombatActorInner;
typedef struct CombatTile CombatTile;
typedef struct CombatantData CombatantData;
typedef struct ConditionInfo ConditionInfo;
typedef struct CursorState CursorState;
typedef struct DDXRecord DDXRecord;
typedef struct DdxChoice DdxChoice;
typedef struct DdxOp DdxOp;
typedef struct DefTrapRecord DefTrapRecord;
typedef struct Dialog Dialog;
typedef struct DialogStyleDescriptor DialogStyleDescriptor;
typedef struct DialogWidget DialogWidget;
typedef struct EncounterActorAux EncounterActorAux;
typedef struct EncounterActorTemplate EncounterActorTemplate;
typedef struct EncounterAnimScratch EncounterAnimScratch;
typedef struct EncounterObjectPose EncounterObjectPose;
typedef struct EncounterObjectState EncounterObjectState;
typedef struct EncounterRecordTemplate EncounterRecordTemplate;
typedef struct EncounterTable EncounterTable;
typedef struct EnginePrefs EnginePrefs;
typedef struct EulerAngles EulerAngles;
typedef struct FontSlotMetrics FontSlotMetrics;
typedef struct GamePositionAndHeading GamePositionAndHeading;
typedef struct GameState GameState;
typedef struct GraphicsContext GraphicsContext;
typedef struct GraphicsContextRender GraphicsContextRender;
typedef struct GridCombatant GridCombatant;
typedef struct IffResLevel IffResLevel;
typedef struct IffResReader IffResReader;
typedef struct ImageRecord ImageRecord;
typedef struct ItemRecord ItemRecord;
typedef struct ItemSlot ItemSlot;
typedef struct ListWidget ListWidget;
typedef struct Mat3x3 Mat3x3;
typedef struct MenuEntry MenuEntry;
typedef struct MenuPage MenuPage;
typedef struct MeshPartRecord MeshPartRecord;
typedef struct Shape Shape;
typedef struct MusicChunkEntry MusicChunkEntry;
typedef struct MusicChunkHeader MusicChunkHeader;
typedef struct OLD_IMAGE_DOS_HEADER OLD_IMAGE_DOS_HEADER;
typedef struct OLD_IMAGE_DOS_RELOC OLD_IMAGE_DOS_RELOC;
typedef struct ObjFixedDiskHeader ObjFixedDiskHeader;
typedef struct ObjFixedLocationCacheEntry ObjFixedLocationCacheEntry;
typedef struct ObjFixedTemplateBuffer ObjFixedTemplateBuffer;
typedef struct PageDirectory PageDirectory;
typedef struct PagedArrayEntry PagedArrayEntry;
typedef struct PerspDiv2Args PerspDiv2Args;
typedef struct PerspDiv2Result PerspDiv2Result;
typedef struct PlayerSpawnRecord PlayerSpawnRecord;
typedef struct PolyEdge PolyEdge;
typedef struct PolyRasterState PolyRasterState;
typedef struct ProximityPolygon ProximityPolygon;
typedef struct ProximityRecord ProximityRecord;
typedef struct ProximityScanHit ProximityScanHit;
typedef struct ProximityVertex ProximityVertex;
typedef struct ProximityZone ProximityZone;
typedef struct ProximityZoneSettings ProximityZoneSettings;
typedef struct R3dRendererState R3dRendererState;
typedef struct RendererVtable RendererVtable;
typedef struct ResourceRemapDesc ResourceRemapDesc;
typedef struct ScriptAnimNode ScriptAnimNode;
typedef struct ScriptBlock ScriptBlock;
typedef struct ScriptObject ScriptObject;
typedef struct SfxLoopPri SfxLoopPri;
typedef struct SkyStrip SkyStrip;
typedef struct Slot Slot;
typedef struct SpellDef SpellDef;
typedef struct SpellDocRow SpellDocRow;
typedef struct SpellSymbolRecord SpellSymbolRecord;
typedef struct StatModPayload StatModPayload;
typedef struct StatSlot StatSlot;
typedef struct StatusEffectSlot StatusEffectSlot;
typedef struct StreamDesc StreamDesc;
typedef struct TileMoveRecord TileMoveRecord;
typedef struct TimerCallback TimerCallback;
typedef struct TimerEventEntry TimerEventEntry;
typedef struct TimerSched TimerSched;
typedef struct TownScene TownScene;
typedef struct TownSceneActor TownSceneActor;
typedef struct Vec3Long Vec3Long;
typedef struct Vec3Short Vec3Short;
typedef struct VfxRec VfxRec;
typedef struct VideoDriverImports VideoDriverImports;
typedef struct VisibleEntryList VisibleEntryList;
typedef struct WorldObject WorldObject;
typedef struct WorldEntity WorldEntity;
typedef struct WorldHotspot WorldHotspot;
typedef struct WorldPos2 WorldPos2;
typedef struct ZoneEntryRecord ZoneEntryRecord;
typedef struct ZoneHotspot ZoneHotspot;
typedef union StreamDescSrcUnion StreamDescSrcUnion;

typedef unsigned long(far *AllocFarFn)(unsigned long size, unsigned short unused,
                                       unsigned short flags);
typedef unsigned short(far *AudioDriverDispatchFn)(unsigned short cmd, unsigned short data);
typedef int(far *BakFcloseFn)(BakFile *stream);
typedef int(far *BakFgetcFn)(BakFile *stream);
typedef BakFile *(far *BakFopenFn)(char *filename, char *mode);
typedef int(far *BakFreadFn)(void *ptr, int size, int count, BakFile *stream);
typedef int(far *BakFseekFn)(BakFile *stream, int offset_lo, int offset_hi, int whence);
typedef int(far *BakFtellFn)(BakFile *stream);
typedef int(far *BakFwriteFn)(void *ptr, int size, int count, BakFile *stream);
typedef int(far *BakPutcFn)(int c, BakFile *stream);
typedef void(far *BakRewindFn)(BakFile *stream);
typedef void(far *BlitChunkyFn)(unsigned char *src_off, unsigned short src_seg, int dst_x,
                                int dst_y, int width_bytes);
typedef void(far *BlitSpriteFn)(int sprite_desc_offset, int dst_x, int dst_y);
typedef void(far *BlitSpriteSimpleFn)(ImageRecord *sprite, int x, int y);
typedef void *(far *CallocFarThunkFn)(unsigned int nitems, unsigned int size);
typedef void(far *CirclePlotterFn)(int x, int y);
typedef int(far *CloseFarThunkFn)(int fd);
typedef void(far *CombatAiActionFn)(CombatActor far *actor);
typedef void(far *CrtExitFn)(void);
typedef void(far *DefaultStubFn)(void);
typedef void(far *EncounterAiActionFn)(CombatActor *actor);
typedef void(far *EncounterAiTurnFn)(CombatActor *actor);
typedef void(far *FARFN)(void);
typedef void(far *FreeThunkFn)(void *ptr);
typedef int(far *FreememFn)(unsigned long ptr);
typedef unsigned int(far *GetpixelFn)(int x, int y);
typedef void(far *GfxDefaultFn)(int arg0, int arg1, int arg2);
typedef unsigned long(far *ImageInstallFn)(unsigned short *image_descs_table,
                                           unsigned short *out_status);
typedef void *(far *MallocFarFn)(unsigned int size);
typedef void(far *PasteRectFn)(void far *src, int x, int y, int width, int height);
typedef void(far *PresentFn)(int x, int y, int w, int h);
typedef void(far *PutpixelFn)(int x, int y, int color);
typedef int(far *ReadFarThunkFn)(int fd, void *buf, unsigned int count);
typedef long(far *RectByteSizeFn)(int width, int height);
typedef void(far *SetBorderColorFn)(int color);
typedef void(far *Slot01Fn)(void);
typedef void(far *Slot02Fn)(void);
typedef void(far *Slot04Fn)(unsigned short x_start, unsigned short y_start, unsigned short width,
                            unsigned short height);
typedef void(far *Slot05Fn)(void far *dst_buffer, unsigned short x_start, unsigned short y_start,
                            unsigned short width, unsigned short height);
typedef void(far *Slot07Fn)(void far *src_buffer, unsigned short x_start, unsigned short y_start,
                            unsigned short width, unsigned short height);
typedef void(far *Slot10Fn)(void);
typedef void(far *Slot11Fn)(void);
typedef void(far *Slot14Fn)(unsigned short far *image_descs_table, unsigned short dst_off,
                            unsigned short dst_seg, unsigned short src_off, unsigned short src_seg);
typedef void(far *Slot18Fn)(unsigned short src_off, unsigned short src_seg, unsigned short dst_x,
                            unsigned short dst_y, unsigned short width_bytes,
                            unsigned short height);
typedef void(far *Slot19Fn)(void);
typedef void(far *Slot20Fn)(unsigned short palette_off, unsigned short palette_seg);
typedef void(far *Slot23Fn)(void);
typedef void(far *Slot24Fn)(short x_pixels, short y_row);
typedef void(far *Slot25Fn)(void);
typedef void(far *Slot27Fn)(void);
typedef void(far *Slot29Fn)(unsigned short sprite_desc_offset, short x, short y,
                            unsigned short flip_flags);
typedef void(far *Slot30Fn)(unsigned short src_off, unsigned short src_seg,
                            unsigned short xy_packed);
typedef void(far *Slot31Fn)(unsigned short desc_list_offset);
typedef void(far *Slot32Fn)(void);
typedef void(far *Slot33Fn)(unsigned short sprite_desc_offset, short x, short y);
typedef void(far *Slot34Fn)(unsigned short start_idx, unsigned short count, unsigned short dst_idx,
                            unsigned short weight);
typedef void(far *Slot35Fn)(unsigned char far *rgb_triplets, unsigned short start_index,
                            unsigned short count);
typedef void(far *Slot36Fn)(void);
typedef void(far *Slot37Fn)(void);
typedef void(far *Slot38Fn)(void);
typedef void(far *Slot39Fn)(void);
typedef void(far *Slot40Fn)(void);
typedef int(far *SpriteRegionSizeFn)(unsigned long sprite_descriptor);
typedef char *(far *StrcatFarFn)(char *dest, char *src);
typedef char *(far *StrchrFarFn)(char *s, int c);
typedef char *(far *StrcpyFarFn)(char *dest, char *src);
typedef void(far *UnimplementedSlotFn)(void);
typedef void(far *UnpackNibblesToPlanesFn)(unsigned char far *src, unsigned char far *dst,
                                           unsigned short count);
typedef void(far *VsyncWaitFn)(int wait_flag);

/** Default focal exponent for a full-screen view: 1 << zoom is the view-plane distance in px. */
#define VIEW_ZOOM_DEFAULT 7

struct EulerAngles {
    short pitch;
    short roll;
    short yaw;
};

/* Screen-space rectangle: origin (x, y) plus extent (width, height). */
struct Rect {
    short x;
    short y;
    short width;
    short height;
};

/* Clip rectangle saved/restored around a world-effect draw.  Member order is
   (xmin, xmax, ymax, ymin), not the canonical xmin/xmax/ymin/ymax order. */
typedef struct SavedClipRect {
    short xmin;
    short xmax;
    short ymax;
    short ymin;
} SavedClipRect;

/* Canonical active clip rectangle (xmin/xmax/ymin/ymax) embedded in the
   graphics context; all four bounds are inclusive screen coordinates. */
typedef struct ClipRect {
    short xmin;
    short xmax;
    short ymin;
    short ymax;
} ClipRect;

/* Tile-space axis-aligned bounding box (byte coordinates).  Member order
   matches the on-disk hotspot record (min_x, max_y, max_x, min_y) rather
   than the canonical order; do not reorder. */
typedef struct TileBBox {
    unsigned char minX;
    unsigned char maxY;
    unsigned char maxX;
    unsigned char minY;
} TileBBox;

/* Absolute rectangle: two corners — top-left (x0,y0) and bottom-right (x1,y1), absolute coords, not extents. */
typedef struct AbsRect {
    short x0;
    short y0;
    short x1;
    short y1;
} AbsRect;

struct ViewContext {
    int zoom;
    WorldEntity *camera;
    EulerAngles viewRotation;
    Rect viewport;
    unsigned char *
        faceMaterials; /* fill-color -> material-id table for the face-shading path; never set by the shipped game */
    unsigned char *colorRemap;
};

struct WorldPos2 {
    long nWorld_x;
    long nWorld_y;
};

struct StatModPayload {
    unsigned short wStatMask;
    short nValue;
    unsigned long dwTApply;
    unsigned long dwTExpiry;
};

struct ActorStatModifier {
    unsigned short wMaskFlags;
    StatModPayload payload;
};

struct ActSpriteCache {
    unsigned short pActorId[6];
    unsigned short pAssetTable[6];
    unsigned char far *pChunk[6];
};

struct AnimSlot {
    ImageRecord ***sprite_header;
    unsigned int sprite_id;
    int facing;
    int current_frame;
    int end_frame;
    short done_flag;
    unsigned int loop_period;
    unsigned int tick_counter;
    unsigned char reverse_flag;
};

struct AudFragNode {
    unsigned short wKey;
    unsigned short wSize;
    AudFragNode far *next;
};

struct AudioListNode {
    AudioListNode far *pNext;
    unsigned char far *pData;
    unsigned short wSortKey;
    unsigned short wId;
    unsigned char bPriority;
    unsigned char filler_d;
    AudioTrackHandle far *pHandle;
    unsigned short wFlags;
};

struct AudioTrackHandle {
    unsigned char pHeader[8];
    unsigned char far *pSubBuffer;
    unsigned char pData[332];
    unsigned char bActive;
    unsigned char pRsvd159[3];
    unsigned char bPriority;
    unsigned char bLoop;
    unsigned char bVolume;
    unsigned char pRsvd15f[7];
    unsigned char far *pScript;
    unsigned char far *pPosition;
    unsigned char abRsvd16e[4];
    AudioTrackHandle far *pNext;
    unsigned char abRsvd176[4];
};

struct BakArchive {
    char name[13];
    char _pad;
    short ordinal;
    FILE *fp;
    unsigned long pos;
    unsigned short flags;
    BakIndexEntry far *index;
};

struct BakArchiveTable {
    BakArchive entries[10];
};

struct BakHandle {
    short archive_idx;
    unsigned long base_offset;
    unsigned long length;
    unsigned long cur_offset;
    unsigned short valid;
    FILE *real_fp;
};

struct BakIndexEntry {
    unsigned long dwHash;
    unsigned long dwBase_offset;
};

struct BmxHeader {
    unsigned short wMagic;
    unsigned short wCompression;
    unsigned short wImageCount;
    unsigned short wCompressedSize;
    unsigned long dwDecompressedSize;
};

struct BookImage {
    short nX;
    short nY;
    unsigned short wImage;
    unsigned short wMirroring;
};

struct BookPage {
    Rect rect;
    unsigned short wDisplayNumber;
    unsigned short wPageNumber;
    unsigned short wPrevPageNumber;
    unsigned short wNextPageNumber;
    unsigned short wPagePointer;
    unsigned short w_pad12;
    unsigned short wImageCount;
    unsigned short wReservedCount;
    unsigned short wShowPageNumber;
    unsigned char pReserved[30];
};

/* wReservedCount text-exclusion rectangles follow the page header in the
 * BOK data: text runs flow around these (illustration areas). */
typedef AbsRect BookReservedRect;

struct BookViewerState {
    short nMarginTop;
    short nMarginBottom;
    short nLineHeight;
    short nVStepIndent;
    short nVStepWrap;
    short nVStepRetract;
    short nVStepUndo;
    unsigned short wAlignment;
    short nFontSlot;
    short nBaselineYOff;
    short nFgColor;
    short nBgColor;
    unsigned short wStyleFlags;
    short nTerminate;
    short nCursorX;
    short nLineY1;
    short nLineYNext;
    short nLineHeightActual;
    short nLineWidthCur;
    short nJustifyOn;
    short nSpaceExtra;
    short nSpaceExtraStep;
    short nSpaceExtraCount;
    short nCharExtra;
    short nCharExtraStep;
    short nCharExtraCount;
    unsigned char huge *pCurChar;
    unsigned char huge *pBreakSave;
    unsigned char far *pResumeSave;
    short pFontSlots[10];
    ImageRecord **pImageRecord;
    unsigned char far *pPalette;
    unsigned char p_pad5a[6];
    short nEmsPage0;
    short nEmsPage1;
};

struct BorlandFarPtr {
    unsigned short offset;
    unsigned short segment;
};

struct WorldPos {
    WorldPos2 xy;
    long nWorld_z;
};

struct CircObj {
    short nRadiusSrc;
    unsigned char bVertexIdx;
    unsigned char bDayColor;
    unsigned char bNightColor;
};

/* Tag-2 payload of a poly-list block (sibling of CircObj); consumed by
 * worldrender_sprite_billboard, which reads it by raw offset (the +2 word is
 * punned into the yAdjust/xOffset byte pair). */
struct SpriteBillboard {
    short spriteIndex;         /* +0 sprite id: paged-array index or sprite-bank index */
    unsigned char yAdjust;     /* +2 vertical draw offset (scaled) */
    unsigned char xOffset;     /* +3 horizontal draw offset (scaled, flip-aware) */
    unsigned char scaleFactor; /* +4 per-sprite scale vs projScale (0 = use projScale) */
    unsigned char vertexIdx;   /* +5 mesh vertex whose world position anchors the sprite */
};

struct CodecVtable {
    unsigned short wBuf_size;
    unsigned short wScratch_size_read;
    unsigned short wScratch_size_write;
    void *pRead_chunk;
    void *pWrite_chunk;
    void *pOpen_write;
    void *pOpen_read;
};

struct StatSlot {
    unsigned char max;
    unsigned char base;
    unsigned char cached;
    unsigned char frac;
    char perm_mod;
};

struct CombatActor {
    char *name;
    unsigned short pSpellsKnown[3];
    StatSlot stats[16];
    char cParty_slot;
    struct Actor far *actor_record;
    CombatActorInner *inner;
};

struct CombatActorInner {
    CombatActor *target;
    short class_id;
    char grid_x;
    char grid_y;
    unsigned char pad_6[2];
    unsigned char flags;
    unsigned char knockback_value;
    short status_head;
    unsigned char pad_c;
    unsigned char knockback_timer;
    unsigned char pad_e[6];
    char dmg_value;
    unsigned char dmg_frames_left;
};

struct GamePositionAndHeading {
    long nX;
    long nY;
    unsigned short wHeading_raw;
};

struct CombatantData {
    unsigned short wMonster_index;
    unsigned short wMovement_type;
    GamePositionAndHeading pos;
    unsigned long dwField0x0e;
    unsigned long dwField0x12;
    unsigned char pPad0[8];
    unsigned long dwField0x1e;
    unsigned long dwField0x22;
    unsigned char pPad1[10];
};

struct CombatTile {
    CombatActor *pOccupant;
    unsigned short wTerrain;
    short nEffectTimer;
};

struct ConditionInfo {
    char pName[11];
    short nStatDelta;
    short nRegenDelta;
    short pExtra[4];
};

struct CursorState {
    short nX;
    short nY;
    short nHotX;
    short nHotY;
    short nWidth;
    short nHeight;
    unsigned short shape;
};

struct DdxChoice {
    unsigned short wCond;
    unsigned short wRange_min_or_mask;
    unsigned short wRange_max_or_chapbits;
    unsigned long dwTarget_key;
};

struct DdxOp {
    unsigned short wOp;
    short nA1;
    short nA2;
    short nA3;
    short nA4;
};

struct DDXRecord {
    unsigned char bStyle;
    unsigned short wSpeaker_id;
    unsigned short wFlags;
    unsigned char bCnt1;
    unsigned char bCnt2;
    unsigned short wBody_len;
};

struct DefTrapRecord {
    unsigned short wGap0;
    unsigned long dwCombat_index;
    unsigned long dwEntry_dialog;
    unsigned long dwScout_dialog;
    unsigned long dwZero;
    GamePositionAndHeading landing_dir1;
    GamePositionAndHeading landing_dir2;
    GamePositionAndHeading landing_dir4;
    GamePositionAndHeading landing_dir8;
    GamePositionAndHeading landing_primary;
    unsigned char bNum_enemies;
    CombatantData pCombatants[7];
    unsigned short wUnknown_u16;
    unsigned short wIs_ambush;
};

struct Dialog {
    DialogWidget **pWidgets;
    short nWidget_capacity;
    short nWidget_count;
    short nFocused_idx;
};

struct DialogStyleDescriptor {
    unsigned char header[12];
    unsigned char applied_state[8];
};

struct DialogWidget {
    char *pText_buf;
    char *pLabel;
    short nCapacity;
    short nLength;
    short nCursor;
    short nFull_length;
    Rect rect;
    short nLabel_x;
    short nLabel_y;
    unsigned char bBg_color;
    unsigned char bFg_color;
    unsigned char bCursor_color;
    unsigned char bLabel_fg;
    unsigned char bSelection_color;
    unsigned char far *pFill_image;
};

struct EncounterActorAux {
    unsigned short wReserved_0;
    short nRecord_idx;
    short nSlot_idx;
    short nEncounter_idx;
    unsigned short wReserved_8;
};

struct EncounterActorTemplate {
    unsigned char kind;
    short nPaged_record_delta;
    short nVariant;
    long nWorld_x_local;
    long nWorld_y_local;
    unsigned short facing;
    long pPoly_x[4];
    long pPoly_y[4];
    unsigned char slack_2f;
};

struct EncounterAnimScratch {
    unsigned char bSpriteDirFrame;
    unsigned char bSpriteDir;
    int nRecordTemplateIdx;
    int nActorSlot;
    int nEncObjStateIdx;
    unsigned char p_fill[2];
};

struct EncounterObjectPose {
    long nWorld_x_offset;
    long nWorld_y_offset;
    short nFacing;
};

struct EncounterObjectState {
    EncounterObjectPose pose;
    unsigned short wKind_state;
};

struct EncounterRecordTemplate {
    EncounterActorTemplate pActors[7];
    unsigned char pPadding[3];
};

struct EncounterTable {
    unsigned char xCoord[40];
    unsigned char yCoord[40];
    unsigned char zCoord[40];
    unsigned char flags[40][38];
};

struct EnginePrefs {
    unsigned char step_speed;
    unsigned char combat_step_speed;
    unsigned char detail_level;
    unsigned char text_speed;
    unsigned char flags;
};

struct FontSlotMetrics {
    unsigned char stride[20];
    unsigned char height[20];
    unsigned char base_char[20];
    unsigned char glyph_count[20];
};

typedef ActorStatModifier ActorStatModRow[8];
typedef ActorStatModRow ActorStatModTable[6];
struct TimerEventEntry {
    unsigned char bKind;
    unsigned char bMode_at_insert;
    unsigned short wSub_id;
    long nValue;
};

struct ObjFixedLocationCacheEntry {
    unsigned short location_id;
    unsigned char pUnk_2[4];
    unsigned long temp_gam_offset;
    unsigned long objfixed_offset;
    unsigned char pUnk_14[8];
};

struct GameState {
    unsigned short nChapter;
    long nParty_gold;
    unsigned long game_time;
    unsigned long dwLastActionTimeSnapshot;
    unsigned char bCombatExitRequest;
    unsigned char nWorldLoopExitRequest;
    unsigned char rsvd_10[1];
    unsigned char nPrevZoneId;
    unsigned char nZoneId;
    unsigned char nPlayerTileX;
    unsigned char nPlayerTileY;
    WorldPos2 zoneDefaultCameraPos;
    unsigned char rsvd_1d[4];
    unsigned short wZoneDefaultCameraHeading;
    unsigned char abTeleportRecord[11];
    short nLastSeenStepSpeed;
    short nLastSeenGridStride;
    short nWorldStepPending;
    unsigned char nWorldStepTickCount;
    unsigned short world_step_tick;
    long lInsetCameraPosZ;
    char pParty_names[6][10];
    CombatActor party_members[6];
    char party_count;
    char party_roster[3];
    struct Actor far *shared_inventory;
    struct Actor far *ground_pile;
    unsigned char bPartyDirtyFlags;
    unsigned int dwPopup_retry_state;
    unsigned short aConditionTickAdvance[6];
    unsigned char abActorStatusRanks[6][7];
    ActorStatModTable aActorStatModifiers;
    short nEvtArgActor0;
    short nEvtArgActor1;
    short nEvtArgStat;
    unsigned char rsvd_59c[2];
    short nEvtArgCount;
    short nEvtArgAux1;
    short nEvtArgItemId;
    short nEvtArgDlgResult;
    long lEvtArgGoldCost;
    long lEvtArgValue;
    long lEvtArgAuxValue;
    short nTimerEventPoolCount;
    TimerEventEntry aTimerEventPool[20];
    unsigned short wPalEventMask;
    short nSpellMenuCasterSlot;
    short nSpellMenuPreselect;
    short nPalFadeDirty;
    short nPrevWorldBrightness;
    short world_brightness;
    short nPalDaynightDelta;
    short nPalAreaBrightness;
    short nPalBrightnessBoost;
    short nPalBlendWeight;
    ObjFixedLocationCacheEntry objfixed_location_cache;
    unsigned char event_bitmap_lo[1063];
    unsigned char event_bitmap_hi[50];
};

/* Fixed party-roster slots: index into GameState.party_members[6]. The
   slot->character binding is engine-fixed (names are *.GAM-seeded but never
   reassigned; see the availability gates in DIALOG.C). A dialog record's
   wSpeaker_id encodes these as slot+1 (1..6), reserving 0 for the narrator. */
#define CHR_LOCKLEAR 0
#define CHR_GORATH 1
#define CHR_OWYN 2
#define CHR_PUG 3
#define CHR_JAMES 4
#define CHR_PATRUS 5

struct GraphicsContext {
    unsigned char bText_fg_color;
    unsigned char bText_bg_color;
    unsigned char bText_style_flags;
    unsigned char bClip_enabled;
    ClipRect clip;
    unsigned char bGfx_fill_enabled;
    unsigned char bGfx_fill_color;
    unsigned char bGfx_outline_color;
    unsigned char bGfx_dither_color;
    unsigned short wVgaPage1Base;
    unsigned short wVgaPage2Base;
    unsigned short wVgaFrontPageBase;
    unsigned short wGfxBlitSrcPage;
    unsigned short wGfxBlitDstPage;
    unsigned char pReserved_0x1a[2];
    unsigned char bBiosCompatible;
    unsigned char bVideoAdapter;
    unsigned char bReserved_0x1e;
    unsigned char bGfxRenderStateFlag;
    unsigned char bReserved_0x20;
    unsigned char bActiveVgaMode;
    unsigned char pReserved_0x22[18];
    unsigned char pFont_glyph_width_bits[20];
    unsigned char pFont_height[20];
    unsigned char pFont_base_char[20];
    unsigned char pFont_glyph_count[20];
    unsigned char pReserved_0x84[40];
    short pPolygonX[20];
    short pPolygonY[20];
    short pPolygonXClipped[20];
    short pPolygonYClipped[20];
    short pPolygonXSaved[20];
    short pPolygonYSaved[20];
    short nPolygonClipVertexCount;
    unsigned char far *pPaletteScratchBuf;
    unsigned char pDriver_scratch_0x1a2[1306];
    unsigned short wTextureIdx;
    unsigned char pReserved_0x6be[42];
    unsigned char bYResDoubled;
    unsigned char bReserved_0x6e9;
};

struct GraphicsContextRender {
    unsigned char pReserved_tail[560];
    unsigned short wSpanTableBufSeg;
    unsigned char bVideoAutoDetectEnabled;
    unsigned char bReserved_0xab5;
};

struct GridCombatant {
    short unused;
    short paged_id;
    unsigned char tile_x;
    unsigned char tile_y;
};

struct IffResLevel {
    unsigned short wEnd_lo;
    unsigned short wEnd_hi_flags;
};

struct IffResReader {
    BakFile *pStream;
    char pChunk_id_stack[25];
    IffResLevel pLevel_cache[7];
    short nDepth;
    short nSkip_count;
    long nCursor;
    unsigned short wChunk_size_lo;
    unsigned short wChunk_size_hi_flags;
};

struct ImageRecord {
    unsigned short wImageData;
    unsigned short wImageOff;
    unsigned short wUnk4;
    short nWidth;
    short nHeight;
};

struct ItemRecord {
    char pName[32];
    unsigned short wFlags;
    unsigned short wName_split_off;
    unsigned short wDamage_class_threshold;
    short nBase_price;
    short nSwing_damage;
    short nThrust_damage;
    short nDefense_or_range_close;
    short nAttack_or_range_long;
    unsigned short wUnk_30;
    unsigned short wDefault_qty_or_1;
    unsigned short wUse_sfx;
    unsigned char bMax_stack;
    unsigned char bCharges_per_use;
    unsigned short wRace_mask;
    unsigned short wSub_flags;
    unsigned short wCategory;
    unsigned short wEffect_arg_a;
    unsigned short wEffect_arg_b;
    unsigned short wEffect_chance_pct;
    unsigned short wEffect_stat_value;
    unsigned short wPlayer_stat_mask;
    short nStat_value;
    unsigned short wWeapon_break_chance_pct;
    short nWeapon_break_amount;
    unsigned short wCondition_floor;
};

struct ItemSlot {
    unsigned char item_id;
    unsigned char condition;
    unsigned short flags;
};

struct ListWidget {
    short nX;
    short nY;
    short nInner_w;
    short nPixel_h;
    short nVisible_rows;
    short nAnchor_x;
    short nAnchor_y;
    unsigned short wCapacity;
    unsigned short wCount;
    unsigned short wScroll_offset;
    char **pLabels;
    unsigned short *pValues;
    MenuEntry *pParent;
};

struct Mat3x3 {
    short pM[9];
    unsigned char bType;
};

struct MenuEntry {
    unsigned short wWidget_type;
    unsigned short wAction_id;
    unsigned char bActive_flag;
    unsigned short wBase_color;
    unsigned short wEnable_gate;
    unsigned short wSub_state;
    Rect rect;
    char *pLabel;
    char *pPrimary_label;
    char *pAlt_label;
    unsigned short wSprite_base;
    unsigned short wCursor_shape;
    unsigned short wClick_flags;
    unsigned short wClick_sfx_id;
};

struct MenuPage {
    unsigned short wWants_screen_save;
    unsigned short wVisible;
    unsigned short wBg_color;
    Rect rect;
    unsigned short wEntry_count;
    MenuEntry *pEntries;
    char *pTitle;
    short nTitle_x;
    short nTitle_y;
    unsigned char far *pBackdrop_buffer;
};

struct MeshPartRecord {
    unsigned char bGroupId;
    unsigned char bEdgeVtxIdx;
    unsigned char bAnchorVtxIdx;
    unsigned char bVertexCount;
    unsigned short wVertexPoolOff;
    short nField6;
    unsigned short wPolyListOff;
    short nSub;
    unsigned short wSubArrOff;
};

struct MusicChunkEntry {
    int nId;
    long nOffset;
};

struct MusicChunkHeader {
    MusicChunkEntry far *pEntries;
    int nMagic;
    int nEntries;
    unsigned char bFlag;
};

struct ObjFixedDiskHeader {
    unsigned char kind;
    unsigned char chap_band;
    unsigned short world_item_id;
    long nWorld_x;
    long nWorld_y;
    unsigned char container_type;
    unsigned char num_items;
    unsigned char capacity;
    unsigned char data_types;
};

struct ObjFixedTemplateBuffer {
    unsigned char pPrefix[6];
    ObjFixedDiskHeader header;
};

struct OLD_IMAGE_DOS_HEADER {
    char e_magic[2];
    unsigned short e_cblp;
    unsigned short e_cp;
    unsigned short e_crlc;
    unsigned short e_cparhdr;
    unsigned short e_minalloc;
    unsigned short e_maxalloc;
    unsigned short e_ss;
    unsigned short e_sp;
    unsigned short e_csum;
    unsigned short e_ip;
    unsigned short e_cs;
    unsigned short e_lfarlc;
    unsigned short e_ovno;
};

struct OLD_IMAGE_DOS_RELOC {
    unsigned short offset;
    unsigned short segment;
};

struct PagedArrayEntry {
    ImageRecord **imageRecord;
    int nCount;
};

struct PageDirectory {
    int nCount;
    BookPage far *pPages[1];
};

struct PerspDiv2Args {
    long nNumX;
    long nDenom;
    long nNumY;
};

struct PerspDiv2Result {
    long nProjX;
    long nProjY;
};

struct PlayerSpawnRecord {
    unsigned char bZoneId;
    unsigned char bTileX;
    unsigned char bTileY;
    unsigned char bSubX;
    unsigned char bSubY;
    unsigned short wCameraHeading;
};

struct PolyEdge {
    long nAcc;
    long nStep;
};

struct PolyRasterState {
    int nRemapTableOff;
    PolyEdge pEdge[3];
};

struct ProximityPolygon {
    unsigned short wVertex_list_offset;
    unsigned char bVertex_count;
    unsigned char bShift;
    short nBase_height;
    unsigned short wReference_vertex_offset;
    unsigned char pUnknown_8[2];
};

struct ProximityRecord {
    unsigned short wRecord_id;
    long nWorld_x;
    long nWorld_y;
    long nZ_base;
    unsigned char pUnknown_e[4];
    short nAngle;
};

struct ProximityScanHit {
    ProximityZone far *pZone_rec;
    ProximityRecord far *pRecord;
    unsigned char bHit_index;
    unsigned char bPad;
    long nZ_delta;
};

struct ProximityVertex {
    unsigned char cCx;
    unsigned char cCy;
    short nX;
    short nY;
};

struct ProximityZone {
    short nMax_x;
    short nMax_y;
    unsigned char bFlags;
    unsigned char bVertex_count;
    unsigned short wVertex_table_offset;
};

struct ProximityZoneSettings {
    unsigned char pPad[2];
    unsigned char bFlat_flag;
    unsigned char bResolution_shift;
};

struct R3dRendererState {
    unsigned long dwMeshVertexFarPtrCache;
    unsigned short wMeshVertexPoolOff;
    unsigned short wMeshPartVertexCount;
    unsigned short wMeshScaleShift;
    unsigned short wMeshScaleResidual;
    unsigned char bMeshRenormCount;
    unsigned char _pad_0xd[1];
    unsigned char bCurMeshLod;
    unsigned char _pad_0xf[1];
    unsigned char bSkipFarEdgeCull;
    unsigned char bActorViewportClip;
    unsigned char _pad_0x12[1];
    unsigned char bPolyNormalFlipped;
    Mat3x3 mat3x3ViewRot;
    Mat3x3 mat3x3ActorRot;
    Mat3x3 mat3x3TempOut;
    long nActorRelX;
    long nActorRelY;
    long nActorRelZ;
    long nActorCamX;
    long nActorCamZ;
    long nActorCamY;
    short nMeshCamOriginX;
    short nMeshCamOriginY;
    short nMeshCamOriginZ;
    short nMeshOriginX;
    short nMeshOriginY;
    short nMeshOriginZ;
    unsigned char _pad_0x71[12];
    short nCamViewYaw;
    short nCamViewPitch;
    unsigned char _pad_0x81[2];
    short nCurModelIdx;
    void far *pCurActorPagedRec;
    unsigned char *pCurMeshPartVisTable;
    long nMeshBoundHalfExtent;
    long nActorBoundExtent;
    long nActorLodZ;
    unsigned short wActorProjScale;
    unsigned char _pad_0x99[6];
    long nActorClampedCamZ;
    short nMeshNormOriginX;
    short nActorFarClipThreshold;
    unsigned char bScreenShift;
    unsigned char _pad_0xa8[1];
    short nViewportCenterX;
    short nViewportCenterY;
};

struct RendererVtable {
    UnimplementedSlotFn far *slot_00_null;
    Slot01Fn far *pfn_blit_glyph_row;
    Slot02Fn far *pfn_draw_line;
    BlitSpriteFn far *pfn_blit_sprite;
    PresentFn far *pfn_present;
    Slot05Fn far *pfn_save_rect;
    RectByteSizeFn far *pfn_rect_byte_size;
    PasteRectFn far *pfn_paste_rect;
    VsyncWaitFn far *pfn_vsync_wait;
    UnimplementedSlotFn far *slot_09_unimplemented;
    Slot10Fn far *pfn_fill_run_a;
    Slot11Fn far *pfn_fill_run_b;
    UnimplementedSlotFn far *slot_12_unimplemented;
    ImageInstallFn far *pfn_image_install;
    Slot14Fn far *pfn_image_decode;
    UnpackNibblesToPlanesFn far *pfn_unpack_nibbles_to_planes;
    UnimplementedSlotFn far *slot_16_unimplemented;
    BlitChunkyFn far *pfn_blit_chunky;
    Slot18Fn far *pfn_blit_chunky_planar_4bit;
    Slot19Fn far *pfn_fill_textured_span_modey_b;
    Slot20Fn far *pfn_palette_set;
    GetpixelFn far *pfn_getpixel;
    PutpixelFn far *pfn_putpixel;
    Slot23Fn far *pfn_blit_rect_buffer;
    Slot24Fn far *pfn_set_buffer_offset;
    UnimplementedSlotFn far *pPfn_set_border_color;
    UnimplementedSlotFn far *slot_26_unimplemented;
    Slot27Fn far *pfn_fill_spans_dithered_modey;
    UnimplementedSlotFn far *slot_28_unimplemented;
    Slot29Fn far *pfn_blit_sprite_master;
    Slot30Fn far *pfn_blit_sprite_flip_h;
    Slot31Fn far *pfn_blit_sprite_flip_v;
    Slot32Fn far *pfn_clear_rect_state;
    BlitSpriteSimpleFn far *pfn_blit_sprite_simple;
    Slot34Fn far *pfn_palette_lerp_dac;
    Slot35Fn far *pfn_dac_write_palette;
    Slot36Fn far *pfn_blit_sprite_planar_rotated;
    Slot37Fn far *pfn_blit_stretched;
    Slot38Fn far *pfn_blit_sprite_chunky_flip;
    Slot39Fn far *pfn_fill_world_textured_span_modey;
    Slot40Fn far *pfn_fill_textured_span_modey;
    UnimplementedSlotFn far *slot_41_unimplemented;
    UnimplementedSlotFn far *slot_42_unimplemented;
    UnimplementedSlotFn far *slot_43_unimplemented;
    UnimplementedSlotFn far *slot_44_unimplemented;
    UnimplementedSlotFn far *slot_45_unimplemented;
    UnimplementedSlotFn far *slot_46_unimplemented;
    UnimplementedSlotFn far *slot_47_unimplemented;
    UnimplementedSlotFn far *slot_48_unimplemented;
    UnimplementedSlotFn far *slot_49_null;
};

struct ResourceRemapDesc {
    unsigned short wIdOrSeg;
    unsigned short wOffset;
    unsigned short wFlags;
};

struct ScriptAnimNode {
    unsigned short wTag;
    unsigned short wIdB;
    unsigned short wPcSaved;
    unsigned short wPcJumpTarget;
    unsigned short wPc;
    unsigned short wDispatchPc;
    unsigned short wFld_0c;
    unsigned short wOpCursor;
    unsigned short wFld_10;
    unsigned short wFld_12;
    unsigned short wFld_14;
    unsigned short wFld_16;
    unsigned short wFld_18;
    unsigned short wFld_1a;
    unsigned short wFld_1c;
    unsigned char bSavedFgColor;
    unsigned char bSavedFillColor;
    unsigned char bSavedClipEnabled;
    short nSavedClipXmin;
    short nSavedClipXmax;
    short nSavedClipYmin;
    short nSavedClipYmax;
    unsigned short wInterval;
    unsigned short wOpState;
    unsigned short wCounter;
    unsigned short wMode;
    unsigned short wCountdown;
    unsigned long dwDeadline;
    unsigned long dwTimerExpiry;
    ScriptAnimNode *pNext;
};

struct ScriptBlock {
    unsigned short wOpcode;
    unsigned short wOperand;
};

struct ScriptObject {
    unsigned short wResourceId;
    short nBlockCount;
    unsigned char far *pTt3_data;
    unsigned char far *pTt3_end;
    unsigned short pAhPagedImage[6];
    unsigned short pAhFont[6];
    unsigned char far *pCachedResource[6];
    unsigned char huge *pFreemem[12];
    unsigned short pRectSrcX[12];
    unsigned short pRectSrcY[12];
    unsigned short pRectDstX[12];
    unsigned short pRectDstY[12];
    unsigned char far *pNext;
    ScriptBlock far *far *pBlocks;
};

struct SfxLoopPri {
    unsigned char bLoop;
    unsigned char bPriority;
};

struct SkyStrip {
    unsigned char bKey;
    unsigned char bHorizonOverride;
    unsigned char bFlags;
    unsigned char bYTop;
    unsigned char bYBot;
    unsigned char bBaseRow;
    unsigned char bEndRow;
    unsigned short wSiBase;
    short nSiStride;
    unsigned char pPad[2];
};

struct Slot {
    short nInitialised;
    short nChannel_count;
    unsigned short far *pScript_buf;
    unsigned short far *pScript_end;
    ScriptObject far *pObjects_head;
    unsigned short wObjects_head_alt;
    unsigned short pChannel_state[80];
    unsigned short pChannel_b2[80];
    unsigned short far *pChannels[80];
    unsigned long pChannel_alt[80];
    unsigned short pOp_lists[80];
};

struct SpellDef {
    char *pName;
    short nCost;
    short nCost_max;
    short nSchool;
    short nSpell_kind;
    short nEffect_sprite_id;
    short nEffect_kind;
    short nInv_component_id;
    short nEffect_subkind;
    short nEffect_magnitude;
    short nEffect_param;
};

struct SpellDocRow {
    char far *pTitle;
    char far *pDesc1;
    char far *pDesc2;
    char far *pDesc3;
    char far *pDesc4;
    char far *pDesc5;
    char far *pDesc6;
};

struct SpellSymbolRecord {
    unsigned short wSpellId;
    short nHotspotX;
    short nHotspotY;
    char cHotkeyLetter;
};

struct StatusEffectSlot {
    short nType;
    short nSource;
    short nDuration_or_hp;
    short nAge_ticks;
    short nNext;
    unsigned char bFlag;
};

union StreamDescSrcUnion {
    unsigned char huge *pBufBase;
    BakFile *pFile;
};

struct StreamDesc {
    unsigned char *pBuf;
    unsigned char huge *pScratch;
    StreamDescSrcUnion src;
    unsigned long dwInPos;
    unsigned long dwInSize;
    unsigned long dwUncompressedSize;
    unsigned long dwOutPos;
    unsigned char bRingHead;
    unsigned char bRingTail;
    unsigned long dwFileStartOff;
    unsigned char bFlags;
};

struct TileMoveRecord {
    unsigned char bSubX;
    unsigned char bSubY;
    short nHeading;
};

struct TimerCallback {
    unsigned short wOff;
    unsigned short wSeg;
};

struct TimerSched {
    unsigned short wCountdown;
    unsigned short wReload;
};

struct TownSceneActor {
    Rect rect;
    unsigned short wChapterMask;
    short nCursorShape;
    char cKind;
    char cClickCount;
    short nNextScene;
    short nAnimChannel;
    unsigned long dwAltDialogKey;
    unsigned long dwDialogKey;
    void far *pDdxRecord;
    short nGateEventId;
    short nGateMin;
    short nGateMax;
};

struct TownScene {
    char pAnimPrefix[13];
    unsigned short wFlags;
    short nExitScene;
    short nMusicTrack;
    short nMusicIntensity;
    short nEntryAnim;
    short nExitAnim;
    short nIdleAnim;
    short nActorCount;
    unsigned long dwDialogKey;
    void far *pDdxRecord;
    void far *pActor;
    TownSceneActor pAActors[1];
};

struct Vec3Long {
    long nX;
    long nY;
    long nZ;
};

struct Vec3Short {
    short nX;
    short nY;
    short nZ;
};

struct VfxRec {
    short nW0;
    short nW1;
    short nW2;
};

struct VideoDriverImports {
    AllocFarFn far *alloc_far;
    FreememFn far *_freemem;
    ReadFarThunkFn far *_read_far_thunk;
    BakFseekFn far *bak_fseek;
    BakFtellFn far *bak_ftell;
    BakFwriteFn far *bak_fwrite;
    BakPutcFn far *bak_putc;
    BakRewindFn far *bak_rewind;
    CloseFarThunkFn far *_close_far_thunk;
    BakFopenFn far *bak_fopen;
    BakFreadFn far *bak_fread;
    BakFcloseFn far *bak_fclose;
    MallocFarFn far *malloc_far;
    CallocFarThunkFn far *calloc_far_thunk;
    BakFgetcFn far *bak_fgetc;
    FreeThunkFn far *free_thunk;
    StrcatFarFn far *strcat_far;
    StrcpyFarFn far *strcpy_far;
    StrchrFarFn far *strchr_far;
};

struct WorldObject {
    unsigned short shapeId;
    WorldPos pos;
    EulerAngles orientation;
    union {
        unsigned short stateBits;
        short animationState;
        EncounterActorAux near *encounterAux;
    } state;
};

struct VisibleEntryList {
    unsigned char bZone;
    unsigned char bParty_x;
    unsigned char bParty_y;
    unsigned char bRef_pair_index;
    unsigned short wEntry_count;
    WorldObject far *pEntries;
};

struct WorldEntity {
    WorldObject base;
    EulerAngles angularVelocity;
    Vec3Short linearVelocity;
    short forwardVelocity;
};

struct WorldHotspot {
    WorldObject far *pEntity;
    unsigned long dwDist;
    Rect rect;
};

struct ZoneEntryRecord {
    unsigned char pHeader[2];
    PlayerSpawnRecord spawn;
    unsigned long dwPromptDlgKey;
    unsigned long dwEntryDlgKey;
    unsigned char pTrailing[2];
};

struct ZoneHotspot {
    unsigned short wKind;
    TileBBox bbox;
    unsigned long dwDef_record_offset;
    unsigned char bInhibitChapter;
    unsigned short wEvent_flag_pre1;
    unsigned short wEvent_flag_pre2;
    unsigned short wEvent_key_post;
    unsigned short wRepeat;
};

typedef DDXRecord far *PDdxRecord;

#endif
