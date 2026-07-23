#include <stdio.h>
#include <stdlib.h>
#include "globals.h"
#include "structs.h"

#include "SRC/GAME/BOOT.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/SYSLOWIO.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/AUDIO/RES/POOL.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/INPUT/TIMER.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/INPUT/INT00.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/SYS/HWSHUT.H"
#include "SRC/GFX/DRIVER/VIDDET.H"
#include "SRC/STREAM/RESLOAD/FONTLOAD.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/INPUT/MOUSE.H"
#include "SRC/R3D/ACTOR/ACTMOTN.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/WIDGET.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/AUDIO/SND/SNDINIT.H"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/SND/SFXTERM.H"
#include "SRC/SYS/EMS.H"
#include "SRC/SYS/MDACON.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/CHARSCRN.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/SCREENS/MAINMENU.H"

unsigned short g_wTimerTickRegistrySlot;
short g_nWorldViewYawNormal;
short g_nWorldViewYawChapter;
short g_nWorldViewFovNormal;
unsigned char g_bssgap_4c53;
unsigned char g_nWorldViewFovChapter;

int g_nEmsInit = 1;
int g_nEmsResourcesEnabled = 0;
unsigned short g_wEmmPagesFree = 0x0000;
char g_szVmcodeOvl[11] = "vmcode.ovl";

#ifdef V102CD
#include "SRC/AUDIO/CDAUDIO.H"
#include "SRC/GAME/CFGPARSE.H"
#include "SRC/GAME/GMAIN.H"
#endif

void boot_start_dat_load(void) {
    BakFile *stream;

    stream = bak_fopen("start.dat", "rb");
    g_render_camera_scratch = actormotion_vec_alloc(0);
    g_render_camera_scratch->base.pos.xy.nWorld_x = g_render_camera_scratch->base.pos.xy.nWorld_y =
        0;
    bak_fread(&g_nWorldViewFovNormal, 2, 1, stream);
    bak_fread(&g_nWorldViewFovChapter, 2, 1, stream);
    g_render_camera_scratch->base.orientation.roll = g_render_camera_scratch->base.orientation.yaw =
        0;
    bak_fread(&g_nWorldViewYawNormal, 2, 1, stream);
    bak_fread(&g_nWorldViewYawChapter, 2, 1, stream);
    bak_fread(&g_grid_tile_size, 2, 1, stream);
    g_active_window = ts_create_fullscreen_view(g_render_camera_scratch);
    bak_fread(&g_active_window->viewport.x, 2, 1, stream);
    bak_fread(&g_active_window->viewport.y, 2, 1, stream);
    bak_fread(&g_active_window->viewport.width, 2, 1, stream);
    bak_fread(&g_active_window->viewport.height, 2, 1, stream);
    bak_fread(g_active_window, 2, 1, stream);
    bak_fclose(stream);
    g_active_window->faceMaterials = NULL;
    return;
}

void boot_active_window_free(void) {
    ts_my_free(g_active_window);
    actormotion_xzfree(g_render_camera_scratch);
    return;
}

void far boot_audio_init(void) {
#ifdef V102CD
    g_cd_present = v102_cddrive_detect(g_cd_drive_letter);
#endif
    if (g_sound_driver == SNDDRV_SBP) {
        audio_driver_init(SNDDRV_ADL, 0, 0, "sx.ovl");
    } else {
        audio_driver_init(g_sound_driver, -2, 0, "sx.ovl");
    }
#ifdef V102CD
    if ((g_sound_driver == SNDDRV_STD || g_sound_driver == SNDDRV_NONE) && g_cd_present != 0) {
        g_sound_driver = (SoundDriverId)9;
    }
#endif
    g_pSfxArchiveStream = cached_file_open("frp.sx");
    audio_preload_ui_sfx();
    pool_init();
}

void boot_sfx_resources_release(void) {
    audio_sfx_stop_environment_set();
    cached_file_close(g_pSfxArchiveStream);
    g_pSfxArchiveStream = (BakFile *)0x0;
#ifdef V102CD
    v102_cdaudio_stop();
#endif
    sfx_subsystem_teardown();
    return;
}

void far boot_party_state_load_from_temp(void) {
    int i;

    gstate_temp_file_read_at((unsigned char far *)&g_gameState, 0L, 0xad7);
    for (i = 0; i < 6; i++) {
        g_gameState.party_members[i].name = g_gameState.pParty_names[i];
        g_gameState.party_members[i].actor_record = actorspawn_objfixed(0, i + 1, 0L);
    }
    g_gameState.shared_inventory = actorspawn_objfixed(0, 7L, 0L);
    g_gameState.ground_pile = actorspawn_objfixed(0, 8L, 0L);
    charscreen_recalc_condition_tick();
}

void far boot_party_state_save_to_temp(void) {
    int i;

    g_wLastTempWriteRecordKind = 0;
    gstate_temp_file_write_at((unsigned char far *)&g_gameState, 0L, 0xad7);
    actorspawn_destroy_and_persist(g_gameState.shared_inventory);
    actorspawn_destroy_and_persist(g_gameState.ground_pile);
    for (i = 0; i < 6; i++) {
        actorspawn_destroy_and_persist(g_gameState.party_members[i].actor_record);
    }
}

void boot_video_init_for_mode(int mode) {
    g_bPaletteCycleEbActive = 0;
    g_cBusyCursorShown = '\0';
    mouse_set_handler_cb(mode ? (void far *)0 : (void far *)syslowio_mouse_handler_cb_noop);
    video_init(mode ? (int)VIDEO_MODE_NEW : (int)VIDEO_MODE_VGA, -1, g_szVmcodeOvl);

    mouse_set_cursor_clip_rect(0, 0, mode ? SCREEN_W_NEW : SCREEN_W_VGA,
                               mode ? SCREEN_H_NEW : SCREEN_H_VGA);
    return;
}

void boot_check_memory_or_die(void) {
    BakFile *stream;
    int file_missing;
    unsigned short emmPagesFree;
    unsigned long requiredBytes;
    unsigned long freeBytes;

    stream = bak_fopen("mem.dat", "rb");
    if (stream != (BakFile *)0x0) {
        file_missing = 0;
        bak_fread(&requiredBytes, 4, 1, stream);
        bak_fclose(stream);
    } else {
        requiredBytes = 0x927c0;
        file_missing = 1;
    }
    emmPagesFree = ems_get_free_memory();
    freeBytes = (unsigned long)(long)alloc_far(0xffffffff, 0);
    if (((int)emmPagesFree < 0x40) || (freeBytes < requiredBytes)) {
        boot_sfx_resources_release();
        if (g_pSfxArchiveStream != (BakFile *)0x0) {
            cached_file_close(g_pSfxArchiveStream);
        }
        if (g_nEmsInit != 0) {
            ems_shutdown();
        }
        hardware_shutdown();
        video_shutdown();
        if (file_missing) {
            printf("You have %lu bytes free...\n", freeBytes);
        }
        printf("You do not have enough memory to run Betrayal at Krondor.\nTry using the Make Boot "
               "Disk option from INSTALL.\n");
        exit(1);
    }
    return;
}

void far boot_engine_hardware_init(void) {
    video_init(8, -1, g_szVmcodeOvl);
    mouse_install();
    screen_cursor_load_pack(0);
    keyboard_install(0);
    mouse_install();
    install_int00_handler();
    timer_install(0xd);
    g_pCodecScratchFp = g_pMainScratchBuf = alloc_far(0x3c8c, 0);
    g_bUnused2cfa[0] = '\x0f';
    g_wVgaScratchPageBase = 0xac00;
    g_wGameFontSlot = font_load("game.fnt");
    font_activate(g_wGameFontSlot);
    g_bPaletteCycleEbActive = 0;
    g_wTimerTickRegistrySlot = registry_slot_alloc((FARFN)syslowio_timer_tick_isr, 4);
    g_cBusyCursorShown = '\0';
    mouse_set_handler_cb((void far *)syslowio_mouse_handler_cb_noop);
    return;
}

void far boot_engine_teardown_and_exit(void) {
    registry_slot_free(g_wTimerTickRegistrySlot);
    palette_cycle_add(-1, 0, 0);
    font_unload(g_wGameFontSlot);
    boot_engine_exit(0);
    return;
}

void boot_startup_screen_show(void) {
    unsigned char far *pal;

    pal = chunk_load_into_slot("options.pal");
    palette_set(pal);
    cache_release(pal);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.bText_fg_color = 0xff;
    g_graphics_context.bText_bg_color = '\0';
    g_graphics_context.bClip_enabled = '\0';
    font_draw_text_ds("Loading Betrayal at Krondor... please wait.", 0, 10);
    vsync_hook(1);
}

void far boot_subsystems_init(void) {
    if (g_bMdaEnabled != 0) {
        mdacon_clear_screen();
    }
    boot_engine_hardware_init();
    boot_startup_screen_show();
    if (g_nEmsInit != 0) {
        if (ems_init() == 0) {
            g_nEmsInit = 0;
        } else {
            if (100 < (int)(g_wEmmPagesFree = ems_get_free_memory())) {
                g_nEmsResourcesEnabled = 1;
            }
        }
        if ((g_wEmmPagesFree != 0) && (g_bMdaEnabled != 0)) {
            mdacon_printf(1, 1, "%d EMM pages available.", g_wEmmPagesFree);
        }
    }
    boot_check_memory_or_die();
    _rand_reset_indices();
    boot_audio_init();
    widget_load_button_sprite_pair("bicons");
    mainmenu_save_cfg_load_settings();
    resblit_load_resource_set_1ec(g_nEmsResourcesEnabled);
    return;
}

void far boot_main_menu_resources_free(void) {
    mainmenu_save_cfg_free_settings();
    widget_free_button_sprite_pair();
    boot_engine_teardown_and_exit();
    return;
}

void boot_engine_exit(int exit_code) {
    boot_sfx_resources_release();
    if (g_pSfxArchiveStream != (BakFile *)0x0) {
        cached_file_close(g_pSfxArchiveStream);
    }
    if (g_nEmsInit != 0) {
        ems_shutdown();
    }
    hardware_shutdown();
    video_shutdown();
    exit(exit_code);
    return;
}
