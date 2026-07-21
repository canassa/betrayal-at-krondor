#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "globals.h"
#include "structs.h"

extern int askabout_dialog_run(unsigned char far *keyword_table, char *npc_name);
extern int askabout_menu_page_run_selection(DDXRecord far *param_1);
extern void askabout_keyword_table_free(void);
extern void askabout_keyword_table_load(void);
extern char *askabout_name_or_keyword_lookup(int id);
extern void askabout_free_paged_image_table(void);
extern void askabout_actor_spr_blit_pal_swap(ushort actor_id, int pal_shift, int frame_idx,
                                             uchar far *pal_buf);
extern int askabout_actor_spr_cache_get(ushort actor_id, int pal_shift);
extern ushort askabout_dispatch_topic(ushort topic_id);
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/GFX/SPRITE/BLITAA.H"
#include "SRC/DIALOG/EVTCOND.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/ITEMTBL.H"


unsigned short *g_pKeywordTable = {0};
MenuPage *g_pKeywordMenuScratch = {0};
ActSpriteCache *g_pActSpriteCache = {0};

void askabout_keyword_table_free(void) {
    if (g_pKeywordTable != (unsigned short *)0) {
        galloc_zfree(g_pKeywordTable);
        g_pKeywordTable = (unsigned short *)0;
    }
    if (g_pKeywordMenuScratch != (MenuPage *)0) {
        galloc_zfree(g_pKeywordMenuScratch);
        g_pKeywordMenuScratch = (MenuPage *)0;
    }
}

void far askabout_keyword_table_load(void) {
    unsigned int size;
    BakFile *stream;
    int i;

    if (g_pKeywordTable == (unsigned short *)0) {
        stream = bak_fopen("KEYWORD.DAT", "rb");
        bak_fread(&size, 2, 1, stream);
        g_pKeywordTable = galloc_safe_zcalloc(size);
        bak_fread(g_pKeywordTable, 1, size, stream);
        bak_fclose(stream);
        for (i = 0; i < (int)*g_pKeywordTable; i = i + 1) {
            *(unsigned short *)((char *)g_pKeywordTable + 2 + i * 2) +=
                (int)((unsigned)g_pKeywordTable - 2);
        }
    }
    if (g_pKeywordMenuScratch == (MenuPage *)0) {

        g_pKeywordMenuScratch = galloc_safe_zcalloc(0x24d);
    }
}

char *askabout_name_or_keyword_lookup(int id) {
    if (id == 0) {
        return 0;
    } else if (id < 7) {
        return *(char **)((int)&g_gameState.zoneDefaultCameraPos.nWorld_x + 3 + id * 0x5f);
    } else {
        askabout_keyword_table_load();

        return (char *)*(unsigned short *)((char *)g_pKeywordTable + (id + 0x124) * 2 + 2);
    }
}

void askabout_free_paged_image_table(void) {
    int i;

    if (g_pActSpriteCache != (ActSpriteCache *)0) {
        i = 0;
        do {
            if (g_pActSpriteCache->pAssetTable[i] != 0) {
                emsimg_free_paged((void *)g_pActSpriteCache->pAssetTable[i]);
            }
            if (g_pActSpriteCache->pChunk[i] != (unsigned char far *)0) {
                cache_release(g_pActSpriteCache->pChunk[i]);
            }
            i = i + 1;
        } while (i < 6);
        galloc_zfree(g_pActSpriteCache);
        g_pActSpriteCache = (ActSpriteCache *)0;
    }
    return;
}

int far askabout_actor_spr_cache_get(ushort actor_id, int pal_shift) {
    int slot;
    int free_slot;
    char fname[16];

    if (g_pActSpriteCache == (ActSpriteCache *)0) {
        g_pActSpriteCache = galloc_safe_zcalloc(0x30);
        memset(g_pActSpriteCache, 0, 0x30);
    }
    slot = 0;
    free_slot = -1;
    while (slot < 6) {
        if (g_pActSpriteCache->pActorId[slot] == actor_id)
            return slot;
        if (g_pActSpriteCache->pActorId[slot] == 0)
            free_slot = slot;
        slot++;
    }
    if ((int)actor_id < 0x31) {
        sprintf(fname, "ACT%03d%s", (int)actor_id, (pal_shift < 0) ? "A.BMP" : ".BMP");
        g_pActSpriteCache->pActorId[free_slot] = actor_id;
        g_pActSpriteCache->pAssetTable[free_slot] = (ushort)resblit_load_asset_table(fname, 2);
        sprintf(fname, "ACT%03d.PAL", (int)actor_id);
        g_pActSpriteCache->pChunk[free_slot] = chunk_load_into_slot(fname);
        *g_pActSpriteCache->pChunk[free_slot] = 0x3f;
    } else {
        g_pActSpriteCache->pAssetTable[free_slot] = 0;
        g_pActSpriteCache->pChunk[free_slot] = (uchar far *)0;
    }
    return free_slot;
}

typedef struct {
    unsigned char r;
    unsigned char g;
    unsigned char b;
} PalEntry;

void far askabout_actor_spr_blit_pal_swap(ushort actor_id, int pal_shift, int frame_idx,
                                          uchar far *pal_buf) {
    int x;
    int y;
    uchar far *local_pal;
    uchar far *chunk_pal;
    ImageRecord **table;
    int i;
    int idx;

    local_pal = pal_buf;
    idx = askabout_actor_spr_cache_get(actor_id, pal_shift);
    table = (ImageRecord **)g_pActSpriteCache->pAssetTable[idx];
    g_pPalQueuedForFlip = g_pActSpriteCache->pChunk[idx];
    g_nPalBlendMode = g_dialog_in_scene ? 0 : 2;
    chunk_pal = g_pPalQueuedForFlip;
    if (chunk_pal != (uchar far *)0) {
        if (*chunk_pal == 0x3f) {
            if (local_pal == (uchar far *)0) {
                local_pal = palette_set((uchar far *)0);
            }
            i = 0;
            do {
                if (i < 0x10 || i >= 0x70) {
                    ((PalEntry far *)chunk_pal)[i] = ((PalEntry far *)local_pal)[i];
                } else if (pal_buf != (uchar far *)0) {
                    ((PalEntry far *)local_pal)[i] = ((PalEntry far *)chunk_pal)[i];
                }
                i++;

            } while (i < 0x100);
        }
    }
    if (table != (ImageRecord **)0 && frame_idx < null_terminated_count(table)) {
        if (pal_shift < 0) {
            resblit_sprite(table[frame_idx], 7, 9);
            g_nPalBlendMode = 0;
        } else {
            x = 0xa0 - table[frame_idx]->nWidth / 2;
            if (pal_shift != 0) {
                y = g_world_widget->viewport.y +
                    (g_world_widget->viewport.height - table[frame_idx]->nHeight) / 2;
            } else {
                y = g_world_widget->viewport.y + g_world_widget->viewport.height -
                    table[frame_idx]->nHeight;
            }
            blit_sprite_aa_edges(table[frame_idx], x, y, g_pPalQueuedForFlip);
        }
    }
    return;
}

ushort far askabout_dispatch_topic(ushort topic_id) {
    ushort avail;

    avail = gstate_event_read(topic_id);
    switch (topic_id) {
    case 0x000b:
        avail = avail && itemtbl_party_count_by_kind(0x3c) == 0;
        break;
    case 0x0009:
        avail = avail && itemtbl_party_count_by_kind(0x65) == 0;
        break;
    case 0x002c:
        avail = avail && gstate_event_read(0x1f6c) != 0;
        break;
    case 0x0075:
        avail = avail && g_gameState.nChapter == 6;
        break;
    case 0x0011:
    case 0x0067:
        avail = avail && evtcond_range_d_read_handler(0x9c44) != 0;
        break;
    case 0x0047:
        avail = avail && (g_gameState.party_members[CHR_OWYN].pSpellsKnown[0] & 0x10) == 0;
        break;
    case 0x006a:
        avail = avail && (g_gameState.party_members[CHR_OWYN].pSpellsKnown[2] & 0x200) == 0;
        break;
    case 0x0084:
        avail = avail && (gstate_event_read(0xc74d) != 0 || gstate_event_read(0x1979) != 0);
        break;
    case 0x00a4:
        avail = avail && gstate_event_read(0x1972) != 0;
        break;
    case 0x0085:
        avail = gstate_event_read(0xdb94);
        break;
    case 0x0082:
        avail = gstate_event_read(0xdb9e);
        break;
    case 0x004c:
    case 0x0094:
        avail = avail && itemtbl_party_count_by_kind(0x48) == 0;
        break;
    case 0x00a3:
        avail = gstate_event_read(0x8e) != 0 && gstate_event_read(0xaa) != 0 &&
                itemtbl_party_count_by_kind(0x7c) != 0;
        break;
    }

    if (gstate_event_read(CONV_TOPIC_INHIBITED(topic_id)) != 0)
        avail = 0;
    return avail;
}

static int far askabout_menu_page_build(unsigned char far *keyword_table) {
    int writeIdx;
    int availCount;
    unsigned char far *kw_ptr;
    MenuEntry *entries;
    MenuPage *src;
    int i;
    int last;

    kw_ptr = keyword_table + 9;
    entries = (MenuEntry *)(g_pKeywordMenuScratch + 1);
    src = g_pKeywordMenuScratch;
    i = availCount = 0;

    for (; i < keyword_table[5]; i++) {
        if (askabout_dispatch_topic(*(unsigned short far *)(kw_ptr + i * 10)) != 0) {
            ++availCount;
        }
    }

    if (availCount == 0) {
        return 0;
    }

    memset(src, 0, 0x1c);
    memset(entries, 0, 0x231);
    i = writeIdx = 0;

    for (; i < keyword_table[5]; i++) {
        if (askabout_dispatch_topic(*(unsigned short far *)(kw_ptr + i * 10)) != 0) {
            entries[writeIdx].wWidget_type =
                (gstate_event_read(KEYWORD_ASKED(*(unsigned short far *)(kw_ptr + i * 10))) != 0)
                    ? 8
                    : 6;
            entries[writeIdx].pPrimary_label =
                (char *)*(unsigned short *)((char *)g_pKeywordTable +
                                            (*(unsigned short far *)(kw_ptr + i * 10) - 1) * 2 + 2);
            entries[writeIdx].wAction_id = i + 0x80;
            ++writeIdx;
        }
    }

    src->wWants_screen_save = 0;
    src->wVisible = 0;
    src->rect.x = 0;
    src->rect.y = 0;
    src->rect.width = 0x140;
    src->rect.height = 200;
    src->pEntries = (MenuEntry *)(g_pKeywordMenuScratch + 1);
    src->wEntry_count = (availCount == 0x10) ? 0x11 : 0x10;

    last = src->wEntry_count - 1;

    for (i = 0; i < (int)src->wEntry_count; i++) {
        if (entries[i].wWidget_type == 0) {
            entries[i].wWidget_type = 8;
        }
        entries[i].bActive_flag = 1;
        entries[i].rect.x = (i % 4) * 0x4b + 0xc;
        entries[i].rect.y =
            (i / 4) * ((availCount != 0x10) + 0xe) + (availCount != 0x10) * 5 + 0x7d;
        entries[i].rect.height = 0xd;
        entries[i].rect.width = 0x46;
        entries[i].wClick_flags = 2;
    }

    entries[last].pPrimary_label = "GoodBye";
    entries[last].wWidget_type = 6;
    entries[last].wAction_id = 1;
    entries[last].rect.x = 0xed;
    entries[last].wClick_flags = 2;

    return 1;
}

int far askabout_dialog_run(unsigned char far *keyword_table, char *npc_name) {
    char speechText[80];
    ushort needsRedraw;
    MenuPage *page;
    uint result;
    int choiceIdx;

    choiceIdx = -1;
    needsRedraw = 1;
    askabout_keyword_table_load();
    if (askabout_menu_page_build(keyword_table) != 0) {
        strcpy(speechText, npc_name);
        strcat(speechText, " asked about:");
        page = g_pKeywordMenuScratch;
        menupage_begin(page);
        menupage_draw(page);
        dialog_draw_speech_bubble((uchar far *)speechText, 0);
        screen_frame_present();
        screen_frame_sync_buffers_rect(0, 200);
        do {
            do {
                if (needsRedraw != 0) {
                    menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x,
                                          page->rect.y);
                    screen_frame_present();
                    menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x,
                                          page->rect.y);
                    needsRedraw = 0;
                }
                screen_frame_present();
                result = menupage_run(page, &needsRedraw);
            } while (result == 0);
            if (result >= 0x80) {
                choiceIdx = result - 0x80;
            }
        } while ((result != 1) && (choiceIdx < 0));
        menupage_end(page);
    }
    return choiceIdx;
}

static void far askabout_menu_wdg_build_global(DDXRecord far *record) {
    int maxw;
    short nHeight;
    short nWidth;
    short nY;
    short nX;
    MenuEntry *entries;
    unsigned char far *kw;
    MenuPage *page;
    int i;
    int tw;

    entries = (MenuEntry *)(g_pKeywordMenuScratch + 1);
    page = g_pKeywordMenuScratch;
    kw = (unsigned char far *)record + 9;
    memset(page, 0, 0x1c);
    dialog_apply_style_state(record, (void far *)&nX);
    page->wWants_screen_save = 0;
    page->wBg_color = 0;
    page->wVisible = 0;
    page->rect.x = nX;
    page->rect.y = nY;
    page->rect.width = nWidth;
    page->rect.height = nHeight;
    page->pEntries = (MenuEntry *)(g_pKeywordMenuScratch + 1);
    page->wEntry_count = record->bCnt1;

    i = maxw = 0;
    for (; i < (int)page->wEntry_count;) {
        memset(&entries[i], 0, 0x21);
        gstate_event_write(*(unsigned short far *)kw, 0);
        entries[i].pPrimary_label = (char *)*(
            unsigned short *)((char *)g_pKeywordTable + (*(unsigned short far *)kw - 1) * 2 + 2);
        if ((tw = font_text_width_ds(entries[i].pPrimary_label) + 10) > maxw)
            maxw = tw;
        i++;
        kw += 10;
    }

    tw = page->rect.width / ((int)page->wEntry_count + 1);
    for (i = 0; i < (int)page->wEntry_count; i++) {
        entries[i].wWidget_type = 6;
        entries[i].wAction_id = i + 0x80;
        entries[i].wBase_color = 0x90;
        entries[i].bActive_flag = 1;
        entries[i].rect.x = (i + 1) * tw + 4 - maxw / 2;
        entries[i].rect.y = nHeight - (g_graphics_context.pFont_height[0] + 0xb);
        entries[i].rect.width = maxw;
        entries[i].rect.height = g_graphics_context.pFont_height[0] + 4;
        entries[i].wClick_flags = 2;
    }
}

static void far askabout_build_party_select_menu(DDXRecord far *record) {
    int max_width;
    short nHeight;
    short nWidth;
    short nY;
    short nX;
    MenuEntry *src;
    MenuPage *page;
    int i;
    int w;

    src = (MenuEntry *)(g_pKeywordMenuScratch + 1);
    page = g_pKeywordMenuScratch;
    memset(page, 0, 0x1c);
    dialog_apply_style_state(record, (void far *)&nX);
    page->wWants_screen_save = 0;
    page->wBg_color = 0;
    page->wVisible = 0;
    page->rect.x = nX;
    page->rect.y = nY;
    page->rect.width = nWidth;
    page->rect.height = nHeight;
    page->pEntries = (MenuEntry *)(g_pKeywordMenuScratch + 1);
    page->wEntry_count = (int)g_gameState.party_count + 1;
    memset(src, 0, page->wEntry_count * 0x21);
    i = max_width = 0;
    for (; i < (int)page->wEntry_count; i++) {
        src[i].pPrimary_label = gstate_party_member_record(i)->name;
        src[i].wAction_id = i + 0x80;
        if ((w = font_text_width_ds(src[i].pPrimary_label) + 10) > max_width)
            max_width = w;
    }
    w = page->rect.width / ((int)page->wEntry_count + 1);
    for (i = 0; i < (int)page->wEntry_count; i++) {
        src[i].wWidget_type = 6;
        src[i].wBase_color = 0x90;
        src[i].bActive_flag = 1;
        src[i].rect.x = (i + 1) * w + 4 - max_width / 2;
        src[i].rect.y = nHeight - (g_graphics_context.pFont_height[0] + 0xb);
        src[i].rect.width = max_width;
        src[i].rect.height = g_graphics_context.pFont_height[0] + 4;
        src[i].wClick_flags = 2;
    }
    src[i - 1].pPrimary_label = "Cancel"; /* i == wEntry_count after loop */
}

int far askabout_menu_page_run_selection(DDXRecord far *record) {
    ushort needsRedraw;
    MenuPage *page;
    uint result;
    uint j;
    int selected;

    selected = -1;
    needsRedraw = 1;
    askabout_keyword_table_load();
    if ((record->wFlags & 0x1000) != 0) {
        askabout_build_party_select_menu(record);
    } else {
        askabout_menu_wdg_build_global(record);
    }
    page = g_pKeywordMenuScratch;
    menupage_begin(page);
    menupage_draw(page);
    screen_frame_present();
    screen_frame_sync_buffers_rect(0, 200);
    do {
        do {
            if (needsRedraw != 0) {
                menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x,
                                      page->rect.y);
                screen_frame_present();
                menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x,
                                      page->rect.y);
                needsRedraw = 0;
            }
            screen_frame_present();
            g_key_ascii = '\0';
            result = menupage_run(page, &needsRedraw);
        } while (result == 0);
        if (result == 1) {
            result = page->pEntries[page->wEntry_count - 1].wAction_id;
        }
        if (result >= 0x80) {
            selected = result - 0x80;
        } else {
            result = toupper((uint)g_key_ascii);
        }
        if (isalpha(result)) {
            int matchCount;
            matchCount = 0;
            for (j = 0; j < page->wEntry_count; j = j + 1) {
                if ((int)*page->pEntries[j].pPrimary_label == (int)result) {
                    selected = j;
                    ++matchCount;
                }
            }
            if (1 < matchCount) {
                selected = -1;
            }
        }
    } while (selected < 0);
    if ((record->wFlags & 0x1000) == 0) {
        uint far *p;
        p = (uint far *)((uchar far *)record + selected * 10 + 9);
        gstate_event_write(*p, 1);
    } else if (page->wEntry_count - 1 == selected) {
        selected = 1;
    } else {
        dialog_cmbt_name_assign_kind(0, (int)g_gameState.party_roster[selected] + 1, 0, 0);
        selected = 0;
    }
    menupage_end(page);
    return selected;
}
