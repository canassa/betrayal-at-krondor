#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gtypes.h"
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/SCREENS/MAINMENU.H"
#include "SRC/WORLD/LOOP/MAP.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/SCREENS/INVENTOR.H"
#include "SRC/SYS/SYSLOWIO.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/MOVE/WORLDMOV.H"
#include "SRC/SCREENS/BOOKVIEW.H"
#include "SRC/SCRIPT/ADSCRIPT.H"
#include "SRC/CHAR/CHARSCRN.H"
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"
#include "vgablit.h"
#include "statname.h"

unsigned char far g_abStatNames[16][15] = {
    "Health",      "Stamina",       "Speed",      "Strength",   "Defense",     "Accy: Crossbow",
    "Accy: Melee", "Accy: Casting", "Assessment", "Armorcraft", "Weaponcraft", "Barding",
    "Haggling",    "Lockpick",      "Scouting",   "Stealth"};

#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/GFX/RASTER/VGABLIT.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/RASTER/CIRCLE.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/INPUT/JOYSTICK.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/INPUT/MOUSE.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/DIALOG/EVTCOND.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/GAME/TIMERPL.H"
#include "SRC/DIALOG/ASKABOUT.H"
#include "SRC/UI/TEXTWRAP.H"
#include "SRC/SCREENS/TOWNSCN.H"
#include "SRC/UI/MODALSCR.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/WORLD/LOOP/WORLDLP.H"
#include "defines.h"


char g_speaker_kinds[6];
char g_speaker_names[6][32];
short g_nDialogAnchorX;
short g_nDialogAnchorY;

int g_nDialogChapterId = -1;
unsigned long g_dwDialogInputCooldown = 0x00000000UL;
unsigned char g_abTextSpeedScale[3] = {0x64, 0x4b, 0x32};
int g_nTabWidth = 0;
DialogStyleDescriptor g_dialog_style_table[7] = {
    {{0x00, 0x00, 0x0a, 0x02, 0x00, 0x00, 0x10, 0x05, 0x02, 0x08, 0x08, 0x14},
     {0x08, 0x00, 0x78, 0x00, 0x31, 0x01, 0x4b, 0x00}},
    {{0x00, 0x01, 0x00, 0x00, 0x01, 0x04, 0x10, 0x03, 0x03, 0x0a, 0x0a, 0x14},
     {0x0d, 0x00, 0x0b, 0x00, 0x26, 0x01, 0x65, 0x00}},
    {{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x05, 0x02, 0x08, 0x08, 0x14},
     {0x08, 0x00, 0x76, 0x00, 0x31, 0x01, 0x49, 0x00}},
    {{0x00, 0x00, 0x0a, 0x02, 0x00, 0x00, 0x10, 0x05, 0x02, 0x08, 0x08, 0x14},
     {0x08, 0x00, 0x78, 0x00, 0x31, 0x01, 0x4b, 0x00}},
    {{0x00, 0x01, 0x00, 0x00, 0x01, 0x04, 0x10, 0x03, 0x03, 0x0a, 0x0a, 0x14},
     {0x0d, 0x00, 0x0b, 0x00, 0x26, 0x01, 0x79, 0x00}},
    {{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x01, 0x01, 0x01, 0x01, 0x14},
     {0x19, 0x00, 0x15, 0x00, 0x0e, 0x01, 0xa0, 0x00}},
    {{0x00, 0x01, 0x00, 0x00, 0x01, 0x04, 0x10, 0x03, 0x03, 0x0a, 0x0a, 0x14},
     {0x0d, 0x00, 0x0b, 0x00, 0x26, 0x01, 0x79, 0x00}}};
unsigned short g_bDialogWorldAnchorValid = 0x0000;
unsigned char g_dialog_running = 0x00;

int dialog_freemem_if_not_null(unsigned char far *ptr) {
    if ((unsigned long)ptr != 0)
        _freemem(ptr);
}

PDdxRecord dialog_load_record_by_key(unsigned long record_key, int use_offset) {
    unsigned long file_offset;
    int record_count;
    DDXRecord header;
    DDXRecord far *record;
    struct {
        unsigned long node_id;
        unsigned long file_off;
    } dir_entry;
    unsigned char far *body_ptr;
    int alloc_size;
    char filename[16];
    BakFile *stream;
    int sub_size;
    int i;

    record = (DDXRecord far *)0;
    if (record_key == 0) {
        return (PDdxRecord)0;
    }
    if (use_offset != 0) {
        file_offset = record_key;
    } else {
        file_offset = 0;
        g_nDialogChapterId = (int)(record_key / 100000);
    }
    strcpy(filename, "DIAL_Z__.DDX");
    filename[6] = g_nDialogChapterId / 10 + '0';
    filename[7] = g_nDialogChapterId % 10 + '0';
    stream = bak_fopen(filename, "rb");
    if (file_offset == 0) {
        bak_fread(&record_count, 2, 1, stream);
        i = file_offset = 0;
        for (; file_offset == 0 && i < record_count; i++) {
            bak_fread(&dir_entry, 8, 1, stream);
            if (dir_entry.node_id == record_key) {
                file_offset = dir_entry.file_off;
            }
        }
    }
    if (file_offset > 0) {
        bak_fseek(stream, file_offset, 0);
        bak_fread(&header, 9, 1, stream);
        sub_size = header.bCnt1 * 10 + header.bCnt2 * 10;
        alloc_size = sub_size + header.wBody_len + 9;
        record = (DDXRecord far *)alloc_far((long)alloc_size, 0);
        *record = header;
        bak_fread_chunked((unsigned char far *)record + 9, 1, (long)sub_size, stream);
        body_ptr = (unsigned char far *)record + sub_size + 9;
        bak_fread_chunked(body_ptr, 1, (unsigned long)header.wBody_len, stream);
    }
    bak_fclose(stream);
    return record;
}

unsigned int far dialog_poll_arrow_or_button(void) {
    unsigned int sc;

    if ((g_dwDialogInputCooldown != 0) && (g_timer_ticks > g_dwDialogInputCooldown)) {
        g_dwDialogInputCooldown = 0;
    }
    if ((sc = kbhit_read() >> 8) != 0) {
        if ((sc == 0x45) || (sc == 0x46)) {
            screen_cursor_show_busy();
            while ((kbhit_read() >> 8) == 0) {
                screen_cursor_restore_shape();
            }
            goto ret0;
        }
        if ((sc != 0x48) && (sc != 0x50) && (sc != 0x4b) && (sc != 0x4d))
            return sc;
        goto ret0;
    }
    if (g_mouse_installed != '\0') {
        if (mouse_button_pressed(0) != 0 || mouse_button_pressed(1) != 0)
            return 0xffff;
    }
    if (g_bJoystick0Installed != '\0') {
        if (joystick_button_pressed(0) != 0 || joystick_button_pressed(1) != 0)
            return 0xffff;
    }
ret0:
    return 0;
}

void far dialog_input_wait_release(int animate_frames, int check_keyboard) {
again:
    if (animate_frames != 0)
        screen_frame_present();
    if (check_keyboard != 0) {
        if (kbhit_read() >> 8 != 0)
            goto again;
    }
    if (g_mouse_installed != '\0') {
        if (mouse_button_pressed(0) != 0 || mouse_button_pressed(1) != 0)
            goto again;
    }
    if (g_bJoystick0Installed != '\0') {
        if (joystick_button_pressed(0) != 0 || joystick_button_pressed(1) != 0)
            goto again;
    }
}

int far dialog_wait_for_acknowledge(unsigned int chars, unsigned int flags, int arg3, int arg4) {
    unsigned int input;
    unsigned long deadline;

    g_dwDialogInputCooldown = 0;
    if (flags & 0x4000) {
        return 1;
    }
    if (flags & 0x40) {
        g_dwDialogInputCooldown =
            (unsigned long)(((long)(unsigned)chars * 12 + 150) *
                            (long)(int)(unsigned)g_abTextSpeedScale[g_engine_prefs->text_speed] /
                            100);
        g_dwDialogInputCooldown =
            g_dwDialogInputCooldown / ((unsigned long)((unsigned)g_gameState.nChapter / 5) + 3) +
            g_timer_ticks;
        screen_cursor_show_busy();
        return 1;
    }
    screen_cursor_restore_shape();
    dialog_input_wait_release(arg4, arg3);
    deadline =
        (unsigned long)(((long)(unsigned)chars * 12 + 150) *
                        (long)(int)(unsigned)g_abTextSpeedScale[g_engine_prefs->text_speed] / 100);
    if (g_engine_prefs->text_speed == 0) {
        if ((flags & 8) == 0) {
            deadline = 0xffffffff;
        } else {
            deadline += g_timer_ticks;
        }
    } else {
        if (flags & 8) {
            deadline = deadline / ((unsigned long)((unsigned)g_gameState.nChapter / 5) + 2);
        }
        deadline += g_timer_ticks;
    }
    while (deadline > g_timer_ticks || (flags & 0x20)) {
        if (arg4 != 0) {
            screen_frame_present();
        }
        if ((input = dialog_poll_arrow_or_button()) != 0) {
            if (input == 1) {
                return 0;
            }
            break;
        }
    }
    dialog_input_wait_release(arg4, 0);
    return 1;
}

void far dialog_input_wait_with_cooldown(int mode) {
    screen_cursor_restore_shape();
    if (g_dwDialogInputCooldown != 0) {
        while (g_dwDialogInputCooldown != 0 && dialog_poll_arrow_or_button() == 0) {
            if (mode == 2) {
                screen_cur_refr_during_long_op();
            } else if (mode != 0) {
                screen_frame_present();
            }
        }
        g_dwDialogInputCooldown = 0;
        dialog_input_wait_release(mode == 1, 1);
    }
}

void dialog_cutscene_op_noop(unsigned char far *record, int a, unsigned int flags) {
    if (flags & 0x80) {
    }
}

static DialogStyleDescriptor *dialog_resolve_style(DDXRecord far *record) {
    unsigned int styleNum;

    styleNum = 2;
    if (g_inventory_screen_mode != 0) {
        styleNum = 5;
    } else if ((g_dialog_in_scene != 0) || (g_dialog_in_char_screen != '\0')) {
        styleNum = 6;
    }
    if (record->wSpeaker_id != 0) {
        styleNum = 1;
    }
    if (record->bStyle != '\0') {
        styleNum = (unsigned int)record->bStyle;
    }
    record->bStyle = (unsigned char)styleNum;
    return &g_dialog_style_table[styleNum] - 1;
}

typedef struct {
    unsigned char b[8];
} StyleState;

void far dialog_apply_style_state(DDXRecord far *record, void far *dest) {
    DdxOp far *sub2;
    DialogStyleDescriptor *desc;
    int i;

    sub2 = (DdxOp far *)(record + 1) + record->bCnt1;
    desc = dialog_resolve_style(record);
    *(StyleState far *)dest = *(StyleState far *)&desc->applied_state;
    for (i = 0; i < record->bCnt2; i++, sub2++) {
        if (sub2->wOp == 6) {
            *(StyleState far *)dest = *(StyleState far *)&sub2->nA1;
        }
    }
}

void far dialog_frame_draw(DDXRecord far *record, int far *rect) {
    DialogStyleDescriptor *desc;
    int inset;
    int fallbackRect[4];
    Slot27Fn far *savedFillFn;

    desc = dialog_resolve_style(record);
    if (rect == (int far *)0) {
        dialog_apply_style_state(record, fallbackRect);
        rect = fallbackRect;
    }
    inset = (desc->header[5] != '\0' && *rect != 0xd) ? 1 : 0;
    g_graphics_context.clip.ymin = g_graphics_context.clip.xmin = 0;

    g_graphics_context.clip.xmax = 0x13f;
    g_graphics_context.clip.ymax = 199;
    g_graphics_context.bClip_enabled = 1;
    if (desc->header[1] != '\0') {
        savedFillFn = g_renderer_vtable.pfn_fill_spans_dithered_modey;
        g_graphics_context.bGfx_fill_enabled = 1;
        g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = 0;

        g_vgablit_si_base = (record->wFlags & 0x8000) ? 0x3d40 : (int)RNDR(0x3d40, 0x3da3);
        g_vgablit_si_mask = 0xff7f;
        g_vgablit_si_stride = 0x43;
        g_renderer_vtable.pfn_fill_spans_dithered_modey =
            (Slot27Fn far *)vgablit_planar_runs_untiled;
        draw_rect_filled(*rect + inset, rect[1], rect[2] - inset, rect[3] - inset);
        g_renderer_vtable.pfn_fill_spans_dithered_modey = savedFillFn;
    } else {
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
        gfx_present_dispatch(*rect, rect[1], rect[2], rect[3]);
    }
    g_graphics_context.bGfx_fill_enabled = 0;
    if (desc->header[4] != '\0' && *rect != 0xd) {
        g_graphics_context.bGfx_outline_color = desc->header[4];
        draw_rect_filled(*rect + inset, rect[1], rect[2] - inset, rect[3] - inset);
    }
    if (desc->header[5] != '\0' && *rect != 0xd) {
        g_graphics_context.bGfx_outline_color = desc->header[5];
        draw_line(*rect + 1, rect[1], *rect + rect[2] - 1, rect[1]);
        draw_line(*rect + rect[2] - 1, rect[1], *rect + rect[2] - 1, rect[1] + rect[3] - 2);
        g_graphics_context.bGfx_outline_color = 0;
        draw_line(*rect, rect[1] + 2, *rect, rect[1] + rect[3] - 1);
        draw_line(*rect, rect[1] + rect[3] - 1, *rect + rect[2] - 4, rect[1] + rect[3] - 1);
    }
    if (record->bStyle - 1 == 5) {
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[9], -4, 0x83, 0);
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[9], 0xea, 3, 3);
    }
}

void far dialog_draw_speech_bubble(char far *text, int y_offset) {
    int width;
    int leftX;

    g_graphics_context.clip.ymin = g_graphics_context.clip.xmin = 0;
    g_graphics_context.clip.xmax = 0x13f;
    g_graphics_context.clip.ymax = 199;
    g_graphics_context.bClip_enabled = 1;
    if (text != 0 && *text != 0) {
        if ((width = font_text_pixel_width(text) + 10) < 0x37) {
            width = 0x37;
        }
        leftX = 0x9e - width / 2;
        g_graphics_context.bGfx_fill_enabled = 0;
        g_graphics_context.bGfx_outline_color = g_graphics_context.bGfx_fill_color = 1;
        draw_circle(7, leftX + 1, y_offset + 0x71);
        g_graphics_context.bGfx_fill_enabled = 1;
        draw_circle(7, leftX + width + 1, y_offset + 0x71);
        draw_line(leftX + 2, y_offset + 0x78, leftX + width + 1, y_offset + 0x78);
        g_graphics_context.bGfx_fill_enabled = 1;
        g_graphics_context.bGfx_outline_color = 0xf;
        g_graphics_context.bGfx_fill_color = 0xb;
        draw_circle(7, leftX, y_offset + 0x70);
        draw_circle(7, leftX + width, y_offset + 0x70);
        g_graphics_context.bGfx_outline_color = 0xb;
        draw_rect_filled(leftX, y_offset + 0x69, width, 0xe);
        g_graphics_context.bGfx_outline_color = 0xf;
        draw_line(leftX, y_offset + 0x69, leftX + width, y_offset + 0x69);
        draw_line(leftX, y_offset + 0x77, leftX + width, y_offset + 0x77);
        g_graphics_context.bText_fg_color = 1;
        font_draw_text_far(text, 0xa1 - font_text_pixel_width(text) / 2, y_offset + 0x6d);
        g_graphics_context.bText_fg_color = 0xa;
        font_draw_text_far(text, 0xa0 - font_text_pixel_width(text) / 2, y_offset + 0x6c);
    }
}

static void far dialog_assign_rand_cmbt_name(int slot_index, int param_2, int param_3) {
    int candidate;
    int retry_ctr;
    int i;

    retry_ctr = 500;
    if (g_gameState.party_count == 0)
        return;
    do {
        candidate = g_gameState.party_roster[RND(g_gameState.party_count)];
        for (i = 0; i < slot_index; i++) {
            if (g_speaker_kinds[i] == candidate)
                candidate = -1;
        }
        switch (param_2) {
        default:
            goto keep;
        case 31:
            if (gstate_event_read(0x7535) == candidate)
                break;
            goto keep;
        case 14:
            if (candidate != 2 && candidate != 3 && candidate != 5)
                break;
            goto keep;
        case 15:
            if (candidate != 0 && candidate != 1 && candidate != 4)
                break;
            goto keep;
        case 16:
            if (candidate != 1 && candidate != 5)
                break;
            goto keep;
        }
        candidate = -1;
    keep:
        if (--retry_ctr < 0) {
            candidate = param_3 ? g_speaker_kinds[param_3 - 1] : g_gameState.party_roster[0];
        }
    } while (candidate < 0);
    g_speaker_kinds[slot_index] = (char)candidate;
    strcpy(g_speaker_names[slot_index], g_gameState.party_members[candidate].name);
}

void far dialog_cmbt_name_assign_kind(int slot, int kind, int aux, int name_token) {
    union {
        char far *fp;
        struct {
            int lo;
            char *dest;
        } s;
    } nameRef;

    g_speaker_kinds[slot] = (char)0xff;

    switch (kind) {
    case 1:
    case 2:
    case 3:
    case 4:
    case 5:
    case 6:
        g_speaker_kinds[slot] = (char)(kind - 1);
        strcpy(g_speaker_names[slot], g_gameState.party_members[kind - 1].name);
        break;

    case 7:
        g_speaker_kinds[slot] = (char)gstate_event_read(0x7535);
        strcpy(g_speaker_names[slot], g_gameState.party_members[g_speaker_kinds[slot]].name);
        break;

    case 10:
    case 30:
        g_speaker_kinds[slot] = (char)g_gameState.nEvtArgActor0;
        strcpy(g_speaker_names[slot], g_gameState.party_members[g_gameState.nEvtArgActor0].name);
        break;

    case 32:
        strcpy(g_speaker_names[slot], askabout_name_or_keyword_lookup(name_token));
        break;

    case 11:
        g_speaker_kinds[slot] = (char)g_gameState.nEvtArgActor1;
        strcpy(g_speaker_names[slot], g_gameState.party_members[g_gameState.nEvtArgActor1].name);
        break;

    case 12:
        g_speaker_kinds[slot] = (char)g_gameState.nEvtArgStat;
        strcpy(g_speaker_names[slot], g_gameState.party_members[g_gameState.nEvtArgStat].name);
        break;

    case 13:
    case 14:
    case 15:
    case 16:
    case 31:
        dialog_assign_rand_cmbt_name(slot, kind, aux);
        break;

    case 17:
        g_speaker_kinds[slot] = (char)0xfe;
        nameRef.s.dest = g_speaker_names[slot];
        combatenc_mnames_lookup_dest(g_gameState.nEvtArgAux1, &nameRef.s.dest);
        break;

    case 18:
        nameRef.fp = (char far *)itemtbl_record_ptr_by_id(g_gameState.nEvtArgItemId);
        _fstrcpy((char far *)(g_speaker_names[slot]), nameRef.fp);
        break;

    case 19:
        gstate_format_money(g_speaker_names[slot], g_gameState.lEvtArgGoldCost, 2);
        break;

    case 20:
        gstate_format_money(g_speaker_names[slot], g_gameState.nParty_gold, 2);
        break;

    case 21:
        ltoa(g_gameState.lEvtArgGoldCost, g_speaker_names[slot], 10);
        break;

    case 22:
        ltoa(g_gameState.lEvtArgValue, g_speaker_names[slot], 10);
        break;

    case 23:
        ltoa(g_gameState.lEvtArgAuxValue, g_speaker_names[slot], 10);
        break;

    case 27:
        _fstrcpy((char far *)g_speaker_names[0], g_abStatNames[(int)g_gameState.lEvtArgValue]);
        itoa(stat_actor_get(&g_gameState.party_members[g_gameState.nEvtArgActor0],
                            (int)g_gameState.lEvtArgValue, 1),
             g_speaker_names[1], 10);
        break;

    case 28:
        strcpy(g_speaker_names[slot], g_bIsRestEncounter != 0 ? "tavernkeeper" : "shopkeeper");
        break;

    case 29:
        _fstrcpy((char far *)(g_speaker_names[slot]),
                 g_abStatNames[(int)g_gameState.lEvtArgAuxValue]);
        break;

    default:
        break;
    }
}

void dialog_render_text_with_tokens(DDXRecord far *record, char far *text, int fg_color, int x_off,
                                    int y_off, int scroll_start) {
    int applied[4];
    int nScratchLen;
    char far *pTitle;
    char buf[50];

    DialogStyleDescriptor *pStyle;
    int idx;
    char *pName;
    char *pEnd;
    unsigned int flags;

    pStyle = dialog_resolve_style(record);
    nScratchLen = 0;
    dialog_apply_style_state(record, applied);
    if (text == (char far *)0) {
        text = (char far *)record + record->bCnt1 * sizeof(DdxChoice) +
               record->bCnt2 * sizeof(DdxOp) + sizeof(DDXRecord);
    }
    g_graphics_context.clip.ymin = g_graphics_context.clip.xmin = 0;
    g_graphics_context.clip.xmax = 0x13f;
    g_graphics_context.clip.ymax = 199;
    g_graphics_context.bClip_enabled = 1;

    if (*text == '#') {
        int centerX = applied[0] + applied[2] / 2;
        int nTitleY = applied[1] + pStyle->header[7];
        text++;
        pTitle = text;
        while (*text != '\0' && *text != '#')
            text++;
        *text = '\0';
        text++;
        if (record->bStyle != 1) {
            sprintf(buf, "- %Fs -", pTitle);
            g_graphics_context.bText_fg_color = 1;
            font_draw_text_far(buf, (centerX + 1) - font_text_pixel_width(buf) / 2, nTitleY + 1);
            g_graphics_context.bText_fg_color = 10;
            font_draw_text_far(buf, centerX - font_text_pixel_width(buf) / 2, nTitleY);
        } else {
            sprintf(buf, "%Fs", pTitle);
            dialog_draw_speech_bubble(buf, 10);
        }
    }

    while (*text != '\0') {
        if (*text == '@') {
            if (isdigit((char)text[1])) {
                text++;
                _ES = ((unsigned *)&text)[1];
                _EBX = *(unsigned long *)&text;
                idx = (char)*(char _es *)_BX - '0';
                if (g_speaker_kinds[idx] == (char)0xfe) {
                    if ((g_speaker_names[idx][0] == 'A' || g_speaker_names[idx][0] == 'O') &&
                        tolower((char)g_pMainScratchBuf[nScratchLen - 2]) == 'a') {
                        pName = g_speaker_names[idx];
                        _fstrcpy(g_pMainScratchBuf + (nScratchLen - 1), "n ");
                        nScratchLen++;
                    } else if (text[1] == 's') {
                        pName = strcpy(buf, g_speaker_names[idx]);
                        pEnd = buf + (strlen(buf) - 1);
                        if (*pEnd == 'h') {
                            strcpy(pEnd, "he");
                        } else if (*pEnd == 'y') {
                            strcpy(pEnd, "ie");
                        }
                    } else {
                        pName = g_speaker_names[idx];
                    }
                } else {
                    pName = g_speaker_names[idx];
                }
            } else {
                pName = g_gameState.party_members[g_gameState.nEvtArgActor0].name;
            }
            _fstrcpy(g_pMainScratchBuf + nScratchLen, pName);
            nScratchLen += strlen(pName);
        } else {
            g_pMainScratchBuf[nScratchLen] = *text;
            nScratchLen++;
        }
        text++;
    }

    g_pMainScratchBuf[nScratchLen] = '\0';
    flags = pStyle->header[6];
    if (record->wFlags & 4)
        flags = flags & 0xf8 | 2;
    applied[0] += pStyle->header[9];
    applied[1] += pStyle->header[7];
    applied[2] -= pStyle->header[9] + pStyle->header[10];
    applied[3] -= pStyle->header[7] + pStyle->header[8];
    if (record->wFlags & 0x200) {

        ((int *)&pTitle)[1] =
            textwrap_compute_lines((long)g_pMainScratchBuf, applied[2], (int *)0, 999) -
            scroll_start;
        applied[3] -= 0x14;
        if (applied[3] < ((int *)&pTitle)[1] * (g_graphics_context.pFont_height[0] + 1))
            applied[1] += 10;
    }
    g_nTabWidth = pStyle->header[11];
    g_graphics_context.bText_style_flags = 1;
    if (pStyle->header[3] != 0) {
        *(char *)&g_graphics_context.bText_fg_color = (char)pStyle->header[3] - 1;
        textwrap_draw_aligned((long)g_pMainScratchBuf, applied[0] + x_off + 1,
                              applied[1] + y_off + 1, applied[2], applied[3], 1, flags,
                              scroll_start);
    }
    g_graphics_context.bText_fg_color = fg_color >= 0 ? (unsigned char)fg_color : pStyle->header[2];
    textwrap_draw_aligned((long)g_pMainScratchBuf, applied[0] + x_off, applied[1] + y_off,
                          applied[2], applied[3], 1, flags, scroll_start);
}

int far dialog_show_by_key(unsigned long key, int interactive) {
    int rect[4];
    DDXRecord far *record;
    int iResult;

    iResult = 1;
    if ((record = dialog_load_record_by_key(key, 0)) != 0) {
        if (record->wFlags & 0x20)
            interactive = 1;
        if (record->wFlags & 0x40)
            interactive = 0;
        dialog_apply_style_state(record, (void far *)rect);
        if (interactive)
            dialog_cutscene_op_noop((unsigned char far *)rect, 0, record->wFlags);
        dialog_frame_draw(record, (int far *)rect);
        dialog_render_text_with_tokens(record, (unsigned char far *)0, -1, 0, 0, 0);
        if (interactive) {
            screen_frame_present();
            screen_frame_sync_buffers_rect(0, 200);
            iResult = dialog_wait_for_acknowledge(g_wTextWrapXAccum, record->wFlags, 1, 1);
            dialog_cutscene_op_noop((unsigned char far *)rect, 1, record->wFlags);
            screen_frame_present();
            dialog_cutscene_op_noop((unsigned char far *)rect, 1, record->wFlags);
            dialog_cutscene_op_noop((unsigned char far *)rect, 2, record->wFlags);
        }
        dialog_freemem_if_not_null((unsigned char far *)record);
        return iResult;
    }
    return 0;
}

void dialog_screen_wipe_rect_or_full(DDXRecord far *pRecord) {
    int rect[4];

    if (pRecord != 0) {
        dialog_apply_style_state(pRecord, rect);
        screen_wipe_horizontal(rect[0], rect[1], rect[2], rect[3]);
    } else {
        screen_wipe_horizontal(0, 0, 320, 200);
    }
}

void dialog_viewport_clip_point(int x, int y) {
    if ((x == -1) && (y == -1)) {
        g_bDialogWorldAnchorValid = 0;
    } else {
        if (x < g_world_widget->viewport.x + 1) {
            x = g_world_widget->viewport.x + 1;
        }
        if (g_world_widget->viewport.x + g_world_widget->viewport.width < x) {
            x = g_world_widget->viewport.x + g_world_widget->viewport.width;
        }
        if (y < g_world_widget->viewport.y) {
            y = g_world_widget->viewport.y;
        }
        if (g_world_widget->viewport.y + g_world_widget->viewport.height < y) {
            y = g_world_widget->viewport.y + g_world_widget->viewport.height;
        }
        g_bDialogWorldAnchorValid = 1;
        g_nDialogAnchorX = x;
        g_nDialogAnchorY = y;
    }
    return;
}

void far dialog_animate_open(DDXRecord far *dialog, int steps) {
    int style[4];
    int anim[4];
    int far *widget_ptr;
    int i;

    if (g_bDialogWorldAnchorValid != 0) {
        dialog_apply_style_state(dialog, (void far *)style);
        widget_ptr = (int far *)((char far *)dialog + (unsigned)dialog->bCnt1 * 10 + 9);
        steps /= 2;
        style[0] = g_nDialogAnchorX - style[2] / 2;
        style[1] = g_nDialogAnchorY - style[3] / 2;
        if (style[0] < 0xe)
            style[0] = 0xe;
        if (style[1] < 0xc)
            style[1] = 0xc;

        if (0x132 < style[0] + style[2])
            style[0] = 0x132 - style[2];
        if (0x6f < style[1] + style[3])
            style[1] = 0x6f - style[3];
        i = 0;
        while (i < (int)(unsigned)dialog->bCnt2) {
            if (widget_ptr[0] == 6) {
                widget_ptr[1] = style[0];
                widget_ptr[2] = style[1];
            }
            i++;
            widget_ptr += 5;
        }
        i = 1;
        if (i < steps) {
            do {
                anim[0] = (style[0] - g_nDialogAnchorX) * i / steps + g_nDialogAnchorX;
                anim[1] = (style[1] - g_nDialogAnchorY) * i / steps + g_nDialogAnchorY;
                anim[2] = style[2] * i / steps;
                anim[3] = style[3] * i / steps;
                dialog_frame_draw(dialog, (int far *)anim);
                screen_frame_present();
                i++;
            } while (i < steps);
        }
        g_bDialogWorldAnchorValid = 0;
    }
}

void far dialog_combatant_name_table_init(void) {
    int i;
#ifdef V102CD
    int found;
#endif

    i = 0;
    do {
        g_speaker_kinds[i] = 0xff;
        g_speaker_names[i][0] = 0;
        i++;
    } while (i < 6);
    dialog_cmbt_name_assign_kind(4, 7, 0, 0);
    dialog_cmbt_name_assign_kind(5, 0xf, 0, 0);
    dialog_cmbt_name_assign_kind(3, 0xe, 0, 0);
    dialog_cmbt_name_assign_kind(0, 0x1f, 0, 0);
#ifdef V102CD
    found = 0;
    for (i = found; i < g_gameState.party_count; i++) {
        if (g_gameState.party_roster[i] == g_gameState.nEvtArgActor0)
            found = 1;
    }
    if (!found)
        g_gameState.nEvtArgActor0 = gstate_event_read(0x7535);
#endif
}

int far dialog_play_record(unsigned long record_key, int modal_flag) {
    int done;
    int scrLoaded;
    int screenDirty;
    int bFirstOpen;
    unsigned short partySpeaker;
    unsigned short npcSpeaker;
    int nSavedMusic;
    int nResult;
    int bNeedImageFree;
    int bAllowFallback;
    int bTopicEmpty;
    unsigned char styleRect[8];
    DDXRecord far *record;
    DdxOp far *op;
    unsigned short savedPalBlend;
    unsigned char far *pSavedPalette;
    unsigned char *pSpeakerName;
    int chapterStack[5];
    int stackDepth;
    long lTimeAccum;
    unsigned long keyStack[5];

    int i;
    int j;

    done = 0;
    scrLoaded = 0;
    screenDirty = 0;
    bFirstOpen = 1;
    partySpeaker = gstate_event_read(0x7535) + 1;
    npcSpeaker = 0;
    nSavedMusic = audio_music_play(-999);
    nResult = 0;
    bNeedImageFree = 0;
    bAllowFallback = 1;
    savedPalBlend = g_nPalBlendMode;
    pSavedPalette = (unsigned char far *)0L;
    pSpeakerName = (unsigned char *)0;
    stackDepth = 0;
    lTimeAccum = 0;
    g_dialog_running = 1;
    if ((record = dialog_load_record_by_key(record_key, 0)) == (DDXRecord far *)0L) {
        g_dialog_running = 0;
    } else {
        dialog_combatant_name_table_init();
        while (((record_key != 0) && (done == 0)) && (record != (DDXRecord far *)0L)) {
            bTopicEmpty = 0;
            if (((scrLoaded != 0) && (record->bStyle == '\0')) && (record->wSpeaker_id == 0)) {
                record->bStyle = '\x06';
            }

            {
                j = 0;
                op = (DdxOp far *)(record + 1) + record->bCnt1;
                while ((int)(unsigned int)record->bCnt2 > j) {
                    if (op->wOp == 1) {
                        dialog_cmbt_name_assign_kind(op->nA1, op->nA2, op->nA3, npcSpeaker);
                    } else if ((op->wOp == 0xc) && (op->nA2 == 0)) {
                        if ((unsigned int)op->nA1 < 1000) {
                            audio_sfx_play_n_times(op->nA1, 0, 1);
                        } else {
                            audio_music_play(op->nA1);
                        }
                    }
                    j = j + 1;
                    op++;
                }
            }

            if (((screenDirty == 0) && ((record->wFlags & 0x100) != 0)) && (modal_flag != 0)) {
                screen_clear_back_buffer();
                screenDirty = 1;
            }

            if (record->wSpeaker_id == 0xfe) {
                record->wSpeaker_id = gstate_event_read(0x7535) + 1;
            }

            if (record->wSpeaker_id == 0xff) {
                record->wSpeaker_id = partySpeaker;
            } else if (record->wSpeaker_id == 0xfd) {
                record->wSpeaker_id = npcSpeaker;
            } else if (record->wSpeaker_id >= 0xf0) {
                int idx = record->wSpeaker_id - 0xf0;
                g_gameState.nEvtArgActor0 = g_speaker_kinds[idx];
                partySpeaker = record->wSpeaker_id = g_gameState.nEvtArgActor0 + 1;
            } else {
                if ((record->wSpeaker_id != 0) && (record->wSpeaker_id < 7)) {
                    partySpeaker = record->wSpeaker_id;
                    g_gameState.nEvtArgActor0 = partySpeaker - 1;
                } else if (record->wSpeaker_id != 0) {
                    npcSpeaker = record->wSpeaker_id;
                }
            }

            if ((record->wFlags & 0x400) != 0) {
                DdxChoice far *p = (DdxChoice far *)(record + 1);
                int j;
                j = i = 0;
                while ((int)(unsigned int)record->bCnt1 > j) {
                    if (askabout_dispatch_topic(p->wCond) != 0) {
                        i = i + 1;
                    }
                    j = j + 1;
                    p++;
                }
                if (i == 0) {
                    j = 0;
                    op = (DdxOp far *)(record + 1) + record->bCnt1;
                    while ((int)(unsigned int)record->bCnt2 > j) {
                        if (op->wOp == 4) {
                            if (op->nA1 == 0x7534) {
                                partySpeaker = op->nA4;
                                g_gameState.nEvtArgActor0 = partySpeaker - 1;
                            } else if (op->nA1 == 0x7538) {
                                npcSpeaker = op->nA4;
                            } else if (((unsigned int)op->nA1 >= 56000) && ((unsigned int)op->nA1 % 10 == 0)) {

                                int bmi = (int)((long)((unsigned long)(unsigned int)op->nA1 + -56000) / 10);
                                g_gameState.event_bitmap_hi[bmi] &= ((unsigned char far *)op)[4];
                                g_gameState.event_bitmap_hi[bmi] |= ((unsigned char far *)op)[5];
                                g_gameState.event_bitmap_hi[bmi] ^= ((unsigned char far *)op)[6];
                            } else {
                                if (op->nA1 != 0) {
                                    gstate_event_write(op->nA1, op->nA4);
                                }
                                if (op->nA2 != 0) {
                                    gstate_event_write(op->nA2, op->nA4);
                                }
                                if (op->nA3 != 0) {
                                    gstate_event_write(op->nA3, op->nA4);
                                }
                            }
                        }
                        j = j + 1;
                        op++;
                    }

                    record->wFlags = record->bCnt1 = record->wSpeaker_id = record->wBody_len =
                        record->bCnt2 = 0;
                    bTopicEmpty = 1;
                }
            }

            if ((record->wSpeaker_id >= CHR_LOCKLEAR + 1) &&
                (record->wSpeaker_id <= CHR_PATRUS + 1)) {
                /* wSpeaker_id-1 = CHR_ slot */
                if (gstate_find_party_slot(&g_gameState.party_members[record->wSpeaker_id - 1]) <
                    0) {
                    if ((((g_gameState.nChapter != 2) || (record->wSpeaker_id != CHR_OWYN + 1)) &&
                         ((g_gameState.nChapter != 8 || (record->wSpeaker_id != CHR_PUG + 1)))) &&
                        ((((g_gameState.nChapter != 1 || (g_gameState.nZoneId != '\v')) ||
                           (record->wSpeaker_id != CHR_JAMES + 1)) &&
                          ((g_gameState.nZoneId != '\x05' ||
                            (record->wSpeaker_id != CHR_PATRUS + 1)))))) {
                        record->wSpeaker_id = gstate_event_read(0x7535) + 1;
                    }
                }
            }

            if ((record->wSpeaker_id != 0) || (record->wBody_len != 0)) {
                pSpeakerName = (unsigned char *)askabout_name_or_keyword_lookup(record->wSpeaker_id & 0xff);
                if ((record->wFlags & 1) == 0) {
                    pSpeakerName = (unsigned char *)0;
                }
                dialog_apply_style_state(record, (void far *)styleRect);
                dialog_cutscene_op_noop((unsigned char far *)styleRect, 0, record->wFlags);
                if ((record->wFlags & 2) != 0) {
                    if (pSavedPalette == (unsigned char far *)0L) {
                        pSavedPalette = palette_set((unsigned char far *)0L);
                    }
                    bNeedImageFree = 1;
                    if (g_dialog_in_scene != 0) {
                        townscene_anim_channel_play_sync(g_dialog_anim_channel);
                        if ((record->wSpeaker_id <= 6) &&
                            (g_pCurScriptObject->pAhPagedImage[5] != 0)) {
                            unsigned int *p = (unsigned int *)g_pCurScriptObject->pAhPagedImage[5];
                            if (p != (unsigned int *)0) {
                                emsimg_map_then_call_180c((unsigned int *)*p, 0xf, 0xb, 0);
                            }
                            askabout_actor_spr_blit_pal_swap(
                                record->wSpeaker_id & 0xff, 0, record->wSpeaker_id >> 8,
                                g_pCurScriptObject->pCachedResource[5]);
                        } else {
                            if (npcSpeaker != 0) {
                                askabout_actor_spr_blit_pal_swap(
                                    npcSpeaker, 0, 0, g_pCurScriptObject->pCachedResource[0]);
                            }
                        }
                    } else {
                        ViewContext widget_save;
                        WorldEntity camera_save;
                        widget_save = *g_world_widget;
                        camera_save = *g_world_camera;
                        if (scrLoaded == 0) {
                            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                            resblit_load_pal_or_stream("Dialog.scr");
                            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                            scrLoaded = 1;
                        }
                        screenDirty = (char)(g_graphics_context.bGfx_fill_enabled = '\x01');
                        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
                        gfx_present_dispatch(0, 0, 0x140, 200);
                        g_world_camera->base.pos.nWorld_z =
                            g_lZoneDefaultZ + g_dwWorldCrossingCoord;
                        g_world_camera->base.orientation.pitch = g_wZoneDefaultYaw;
                        g_world_widget->colorRemap = NULL;
                        if (record->wSpeaker_id <= 6) {
                            if (gstate_is_party_member(record->wSpeaker_id - 1) != 0) {
                                int m;
                                g_world_camera->base.orientation.yaw =
                                    camera_save.base.orientation.yaw ^ 0x8400;
                                j = 0;
                                m = 0;
                                for (; j < g_gameState.party_count; j = j + 1) {
                                    if ((int)g_gameState.party_roster[j] ==
                                        record->wSpeaker_id - 1) {
                                        m = j;
                                    }
                                }

                                if (m == 1) {
                                    g_world_camera->base.orientation.yaw -= 0x2800;
                                } else if (m == 2) {
                                    g_world_camera->base.orientation.yaw += 0x2800;
                                }
                            }
                        }
                        world_render_frame(1);
                        g_graphics_context.bGfx_outline_color = '\x06';
                        g_graphics_context.bGfx_fill_enabled = g_graphics_context.bClip_enabled =
                            '\0';
                        draw_rect_filled(
                            g_graphics_context.clip.xmin - 1, g_graphics_context.clip.ymin - 1,
                            (g_graphics_context.clip.xmax - g_graphics_context.clip.xmin) + 3,
                            (g_graphics_context.clip.ymax - g_graphics_context.clip.ymin) + 3);
                        *g_world_camera = camera_save;
                        *g_world_widget = widget_save;
                        askabout_actor_spr_blit_pal_swap(record->wSpeaker_id & 0xff, 0,
                                                         record->wSpeaker_id >> 8, (unsigned char far *)0L);
                        g_graphics_context.bClip_enabled = '\x01';
                    }
                } else {
                    if ((scrLoaded != 0) || (record->bStyle - 1 == 5)) {
                        if (scrLoaded == 0) {
                            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                            resblit_load_pal_or_stream("Dialog.scr");
                            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                            scrLoaded = 1;
                            g_bDialogWorldAnchorValid = 0;
                        }
                        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
                        gfx_present_dispatch(0, 0, 0x140, 200);
                    }
                }
                if (record->wSpeaker_id != 0) {
                    if (record->wBody_len != 0) {
                        dialog_frame_draw(record, (int far *)0L);
                        dialog_render_text_with_tokens(record, (unsigned char far *)0L, -1, 0, 0, 0);
                    }
                    if (record->wSpeaker_id < 0x46) {
                        dialog_draw_speech_bubble((unsigned char far *)pSpeakerName, 0);
                    }
                } else {
                    if ((g_bDialogWorldAnchorValid != 0) && (bFirstOpen != 0)) {
                        dialog_animate_open(record, 0x14);
                        if (record->wBody_len != 0) {
                            dialog_frame_draw(record, (int far *)0L);
                            dialog_render_text_with_tokens(record, (unsigned char far *)0L, -1, 0, 0, 0);
                        }
                    } else {
                        if (record->wBody_len != 0) {
                            dialog_frame_draw(record, (int far *)0L);
                            dialog_render_text_with_tokens(record, (unsigned char far *)0L, -1, 0, 0, 0);
                        }
                        if ((record->wFlags & 0x2000) == 0) {
                            dialog_screen_wipe_rect_or_full(
                                record->bStyle - 1 == 5 ? (DDXRecord far *)0L : record);
                        }
                    }
                }
                screen_frame_present();
                screen_frame_sync_buffers_rect(0, 200);
                dialog_input_wait_release(1, 1);
                bFirstOpen = 0;
            }

            {
                j = 0;
                op = (DdxOp far *)(record + 1) + record->bCnt1;
                while ((int)(unsigned int)record->bCnt2 > j) {
                    switch (op->wOp) {
                    case 2:
                        if ((char)op->nA1 == '5') {
                            g_gameState.nParty_gold += (long)(unsigned int)op->nA2 * 10;
                        } else if ((char)op->nA1 == '6') {
                            g_gameState.nParty_gold += (long)(unsigned int)op->nA2;
                        } else {
                            ItemSlot slot;
                            int handle;
                            unsigned int speakerSel;
                            speakerSel = (unsigned int)((unsigned char far *)&op->nA1)[1] & 0x7f;
                            handle = itemtbl_load();
                            slot.item_id = (unsigned char)op->nA1;
                            slot.condition = (unsigned char)op->nA2;
                            slot.flags = 0;
                            if ((int)speakerSel > 1) {
                                if (cmbinv_actor_acquire_item(
                                        g_gameState.party_members[(g_speaker_kinds - 2)[speakerSel]]
                                            .actor_record,
                                        (ItemSlot far *)&slot) != 0) {
                                    g_gameState.nParty_gold -= (long)(unsigned int)op->nA3;
                                }
                            } else {
                                for (i = 0; i < g_gameState.party_count; i = i + 1) {
                                    if (cmbinv_actor_acquire_item(
                                            gstate_party_member_record(i)->actor_record,
                                            (ItemSlot far *)&slot) != 0) {
                                        g_gameState.nParty_gold -=
                                            (unsigned int)op->nA3 / (unsigned int)(int)g_gameState.party_count;
                                    }
                                }
                            }
                            if ((int)handle != 0) {
                                itemtbl_free();
                            }
                            if (g_gameState.nParty_gold < 0) {
                                g_gameState.nParty_gold = 0;
                            }
                        }
                        break;
                    case 3:
                        if (op->nA1 == 0x35) {
                            g_gameState.nParty_gold -= (long)(unsigned int)op->nA2 * 10;
                        } else if (op->nA1 == 0x36) {
                            g_gameState.nParty_gold -= (long)(unsigned int)op->nA2;
                        } else {
                            unsigned int tblLoadedHere;
                            Actor far *pActor;
                            int slotIdx;
                            tblLoadedHere = itemtbl_load();
                            for (i = 0; i <= g_gameState.party_count; i = i + 1) {

                                pActor =
                                    (g_gameState.party_count == i)
                                        ? g_gameState.shared_inventory
                                        : g_gameState.party_members[g_gameState.party_roster[i]]
                                              .actor_record;
                                for (slotIdx = 0; slotIdx < pActor->itemCount;
                                     slotIdx = slotIdx + 1) {
                                    if (((unsigned int)ACTOR_ITEM(pActor, slotIdx).item_id ==
                                         (unsigned int)op->nA1) &&
                                        (ACTOR_ITEM(pActor, slotIdx).item_id != 'x' ||
                                         (unsigned int)ACTOR_ITEM(pActor, slotIdx).condition ==
                                             (unsigned int)op->nA2)) {
                                        pActor->needsFlush = TRUE;
                                        ACTOR_ITEM(pActor, slotIdx) = ACTOR_ITEM(
                                            pActor, pActor->itemCount = pActor->itemCount - 1);

                                        i = slotIdx = 999;
                                    }
                                }
                            }
                            if (tblLoadedHere != 0) {
                                itemtbl_free();
                            }
                        }
                        if (g_gameState.nParty_gold < 0) {
                            g_gameState.nParty_gold = 0;
                        }
                        break;
                    case 23: {
                        unsigned int n;
                        for (n = 0; (n < (unsigned int)op->nA2); n = n + 1) {
                            itemtbl_pty_consum_one_kind(op->nA1);
                        }
                    } break;
                    case 4:
                        if (op->nA1 == 0x7534) {
                            partySpeaker = op->nA4;
                            g_gameState.nEvtArgActor0 = partySpeaker - 1;
                        } else if (op->nA1 == 0x7538) {
                            npcSpeaker = op->nA4;
                        } else if (((unsigned int)op->nA1 >= 56000) && ((unsigned int)op->nA1 % 10 == 0)) {

                            int bmi = (int)((long)((unsigned long)(unsigned int)op->nA1 + -56000) / 10);
                            g_gameState.event_bitmap_hi[bmi] &= ((unsigned char far *)op)[4];
                            g_gameState.event_bitmap_hi[bmi] |= ((unsigned char far *)op)[5];
                            g_gameState.event_bitmap_hi[bmi] ^= ((unsigned char far *)op)[6];
                        } else {
                            if (op->nA1 != 0) {
                                gstate_event_write(op->nA1, op->nA4);
                            }
                            if (op->nA2 != 0) {
                                gstate_event_write(op->nA2, op->nA4);
                            }
                            if (op->nA3 != 0) {
                                gstate_event_write(op->nA3, op->nA4);
                            }
                        }
                        break;
                    case 5: {
                        short far *q = &op->nA1;
                        screen_cursor_show_busy();
                        bNeedImageFree = 1;
                        for (i = 0; *q != 0 && i < 4; i = i + 1, q++) {
                            askabout_actor_spr_cache_get((unsigned short)*q, 0);
                        }
                    } break;
                    case 17:
                        g_gameState.party_count = (char)op->nA1;
                        g_gameState.party_roster[0] = (char)op->nA2;
                        g_gameState.party_roster[1] = (char)op->nA3;
                        g_gameState.party_roster[2] = (char)op->nA4;
                        worldloop_pty_stat7_flag_cd();
                        break;
                    case 10:
                        if ((unsigned int)op->nA1 > 1) {
                            g_gameState.nEvtArgDlgResult = stat_actor_get(
                                &g_gameState.party_members[g_speaker_kinds[(unsigned short)op->nA1 - 2]],
                                op->nA2, 0);
                        } else {
                            g_gameState.nEvtArgDlgResult =
                                stat_party_find_extreme(op->nA2, 0, (short *)0);
                        }
                        break;
                    case 9: {
                        unsigned int speakerSel;
                        int val;
                        int amt;
                        unsigned int amt_snap;
                        unsigned int nA4_snap;
                        speakerSel = (unsigned int)(unsigned char)op->nA1;
                        val = ((unsigned char far *)&op->nA1)[1];
                        amt = (unsigned short)op->nA3;
                        amt_snap = (unsigned short)op->nA3;
                        nA4_snap = (unsigned short)op->nA4;
                        if (nA4_snap != amt_snap) {
                            amt = amt + RND(nA4_snap - amt_snap);
                        }
                        if (op->nA2 == 0x10) {
                            val = 'd';
                        }
                        if ((int)speakerSel > 1) {
                            stat_combatant_modify(
                                &g_gameState.party_members[(g_speaker_kinds - 2)[speakerSel]],
                                op->nA2, (long)amt, val);
                        } else {
                            stat_party_broadcast_status_op(op->nA2, (long)amt, val);
                        }
                    } break;
                    case 8: {
                        unsigned int amt;
                        unsigned int amt_snap;
                        unsigned int nA4_snap;
                        amt = (unsigned short)op->nA3;
                        amt_snap = (unsigned short)op->nA3;
                        nA4_snap = (unsigned short)op->nA4;
                        if (nA4_snap != amt_snap) {
                            amt = amt + RND(nA4_snap - amt_snap);
                        }
                        if ((unsigned int)op->nA1 > 1) {
                            stat_combatant_apply_delta(
                                &g_gameState.party_members[g_speaker_kinds[(unsigned short)op->nA1 - 2]],
                                op->nA2, amt);
                        } else {
                            i = 0;
                            while (i < g_gameState.party_count) {
                                stat_combatant_apply_delta(
                                    &g_gameState.party_members[g_gameState.party_roster[i]],
                                    op->nA2, amt);
                                i = i + 1;
                            }
                        }
                    } break;
                    case 18:
                        if ((unsigned int)op->nA1 > 1) {
                            stat_combatant_heal(
                                &g_gameState.party_members[g_speaker_kinds[(unsigned short)op->nA1 - 2]],
                                op->nA2);
                        } else {
                            stat_party_heal_all(op->nA2);
                        }
                        break;
                    case 12:
                        if (op->nA2 == 1) {
                            if ((unsigned int)op->nA1 < 1000) {

                                audio_sfx_play_n_times(op->nA1, 0, 1);
                                break;
                            }
                            audio_music_play(op->nA1);
                        }
                        break;
                    case 13:
                        lTimeAccum = lTimeAccum + *(long far *)&op->nA1;
                        break;
                    case 15:
                        askabout_free_paged_image_table();
                        break;
                    case 14:
                        gstate_event_write(op->nA1, 1);
                        timerpool_upsert(4, op->nA1, 0x40, *(unsigned long far *)&op->nA3);
                        break;
                    case 22:
                        timerpool_upsert((unsigned int)(unsigned char)op->nA1, op->nA2,
                                         (unsigned int)((unsigned char far *)&op->nA1)[1], *(unsigned long far *)&op->nA3);
                        break;
                    case 11:
                        audio_sfx_play_n_times(op->nA1, 0, 1);
                        break;
                    case 19:
                        combat_actor_bitmap_set_bit(
                            (int)&g_gameState.party_members[g_speaker_kinds[(unsigned short)op->nA1 - 2]],
                            op->nA2);
                        break;
                    case 20:
                        modalscreen_teleport_dat_load(op->nA1);
                        break;
                    case 7:
                        evtcond_dialog_action_dispatch(op);
                        break;
                    }
                    j = j + 1;
                    op++;
                }
            }

            if ((record->wFlags & 0x400) != 0) {
                bAllowFallback = 0;
                i = askabout_dialog_run(&record->bStyle, (char *)pSpeakerName);
                if (i >= 0) {
                    gstate_event_write(KEYWORD_ASKED(((DdxChoice far *)(record + 1))[i].wCond), 1);
                    record_key = ((DdxChoice far *)(record + 1))[i].dwTarget_key;
                } else {
                    record_key = 0;
                }
            } else if ((record->wFlags & 0x200) != 0) {
                i = 0;
                while (g_wTextWrapLinesRemaining != 0) {
                    dialog_frame_draw(record, (int far *)0L);
                    dialog_render_text_with_tokens(record, (unsigned char far *)0L, -1, 0, 0, i);
                    if (record->wSpeaker_id < 0x46) {
                        dialog_draw_speech_bubble((unsigned char far *)pSpeakerName, 0);
                    }
                    screen_frame_present();
                    screen_frame_sync_buffers_rect(0, 200);
                    if (g_wTextWrapLinesRemaining != 0) {
                        dialog_wait_for_acknowledge(g_wTextWrapXAccum, 0, 0, 1);
                    }
                    i = i + g_wTextWrapLinesDrawn;
                }
                nResult = askabout_menu_page_run_selection(record);
                record_key = ((DdxChoice far *)(record + 1))[nResult].dwTarget_key;
            } else {
                if (record->wBody_len != 0) {
                    i = 0;
                    if (g_wTextWrapLinesRemaining != 0) {
                        *(short far *)&record->wFlags &= ~0x40;
                    }
                    do {
                        if (dialog_wait_for_acknowledge(
                                g_wTextWrapXAccum,
                                g_wTextWrapLinesRemaining != 0 ? 0 : record->wFlags, 0, 1) == 0) {
                            g_bCutsceneEscPressed = '\x01';
                        }
                        if ((record->wFlags & 0x40) != 0) {
                            scrLoaded = 0;
                        }
                        if ((done != 0) || (g_wTextWrapLinesRemaining == 0))
                            break;
                        i = i + g_wTextWrapLinesDrawn;
                        dialog_frame_draw(record, (int far *)0L);
                        dialog_render_text_with_tokens(record, (unsigned char far *)0L, -1, 0, 0, i);
                        if (record->wSpeaker_id < 0x46) {
                            dialog_draw_speech_bubble((unsigned char far *)pSpeakerName, 0);
                        }
                        screen_frame_present();
                        screen_frame_sync_buffers_rect(0, 200);
                    } while (done == 0);
                }
                if ((record->wFlags & 0x800) != 0) {

                    record_key =
                        ((DdxChoice far *)(record + 1))[(int)RND(record->bCnt1)].dwTarget_key;
                } else {

                    {
                        unsigned int bMatched;
                        DdxChoice far *pChoice;
                        pChoice = (DdxChoice far *)(record + 1);
                        j = (int)(record_key = (unsigned long)(unsigned int)(bMatched = 0));
                        for (; bMatched == 0 && (int)(unsigned int)record->bCnt1 > j; j++, pChoice++) {
                            if (pChoice->wCond != 0) {
                                if ((pChoice->wCond >= 56000) && (pChoice->wCond % 10 == 0)) {
                                    unsigned char far *pc = (unsigned char far *)pChoice;
                                    unsigned char bMask;
                                    int bmi;
                                    bMask = (g_gameState.nChapter < 9)
                                                ? (unsigned char)(1 << (g_gameState.nChapter - 1))
                                                : 0x80;
                                    bmi = (int)((long)((unsigned long)pChoice->wCond + -56000) / 10);
                                    if (pc[4] != '\0') {
                                        if ((((g_gameState.event_bitmap_hi[bmi] ^ pc[2]) & pc[3]) !=
                                             pc[3]) ||
                                            ((pc[5] & bMask) == 0))
                                            continue;
                                    take_via_pc:
                                        record_key = ((DdxChoice far *)pc)->dwTarget_key;
                                        bMatched = 1;
                                        continue;
                                    }
                                    if ((((g_gameState.event_bitmap_hi[bmi] ^ pc[2]) & pc[3]) !=
                                         0) ||
                                        ((pc[5] & bMask) != 0))
                                        goto take_via_pc;
                                    continue;
                                }
                                {
                                    unsigned short eventVal;
                                    eventVal = gstate_event_read(pChoice->wCond);
                                    if ((eventVal < pChoice->wRange_min_or_mask) ||
                                        (pChoice->wRange_max_or_chapbits < eventVal))
                                        continue;
                                }
                            }
                            record_key = pChoice->dwTarget_key;
                            bMatched = 1;
                        }
                    }
                }
            }
            {
                int j = 0;
                op = (DdxOp far *)(record + 1) + record->bCnt1;
                while ((int)(unsigned int)record->bCnt2 > j) {
                    if ((op->wOp == 0x10) && (record_key != 0)) {
                        chapterStack[stackDepth] = g_nDialogChapterId;
                        keyStack[stackDepth] = *(unsigned long far *)&op->nA1;
                        stackDepth++;
                    } else if ((op->wOp == 0xc) && (op->nA2 == 2)) {
                        if ((unsigned int)op->nA1 < 1000) {
                            audio_sfx_play_n_times(op->nA1, 0, 1);
                        } else {
                            audio_music_play(op->nA1);
                        }
                    } else if (op->wOp == 0x15) {
                        done = 1;
                        nResult = op->nA1;
                    }
                    j = j + 1;
                    op++;
                }
            }

            if ((record->wSpeaker_id != 0) || (record->wBody_len != 0)) {
                dialog_cutscene_op_noop((unsigned char far *)styleRect, 1, record->wFlags);
                screen_frame_present();
                dialog_cutscene_op_noop((unsigned char far *)styleRect, 1, record->wFlags);
                dialog_cutscene_op_noop((unsigned char far *)styleRect, 2, record->wFlags);
            }
            dialog_freemem_if_not_null(&record->bStyle);
            record = (DDXRecord far *)0L;
            if ((record_key == 0) && (stackDepth != 0)) {
                stackDepth--;
                g_nDialogChapterId = chapterStack[stackDepth];
                record_key = keyStack[stackDepth];
                if ((bTopicEmpty != 0) && (bAllowFallback != 0)) {
                    record_key = 0x801e849bUL;
                }
            }
            if ((record_key != 0) && (done == 0)) {
                unsigned int useOffset = (unsigned int)((record_key & 0x80000000UL) == 0);
                record = dialog_load_record_by_key(record_key & 0x7fffffffUL, useOffset);
            }
        }

        g_bDialogWorldAnchorValid = 0;
        if (bNeedImageFree != 0) {
            askabout_free_paged_image_table();
        }
        askabout_keyword_table_free();
        if (pSavedPalette != (unsigned char far *)0L) {
            g_pPalQueuedForFlip = pSavedPalette;
            g_nPalBlendMode = savedPalBlend;
        }
        audio_music_play(nSavedMusic);
        if (!((((scrLoaded == 0) || (g_dialog_in_scene != 0)) ||
               ((i = g_dialog_in_char_screen) != 0)) ||
              (g_inventory_screen_mode != 0))) {
            g_nSceneReloadPending = 1;
            g_nMapReloadPending = 1;
        } else {
            if (screenDirty != 0) {
                screen_clear_both_pages();
            }
        }
        g_dialog_running = 0;
        if (lTimeAccum != 0) {
            unsigned int recomputeParty;
            int over = (0x5460 < lTimeAccum);
            recomputeParty = (unsigned int)(g_dwDialogInputCooldown == 0);
            for (; 0 < lTimeAccum; lTimeAccum -= 0x708) {
                if (over) {
                    g_gameState.dwLastActionTimeSnapshot = g_gameState.game_time;
                }
                gstate_advance_time(0x708 < lTimeAccum ? 0x708 : lTimeAccum, 1, recomputeParty, 0,
                                    0);
            }
            if (over) {
                g_gameState.dwLastActionTimeSnapshot = g_gameState.game_time;
            }
        }
        dialog_input_wait_release(0, 1);
        if (done != 0) {
            return (nResult < 0) ? nResult : -1;
        }
    }
    return nResult;
}
