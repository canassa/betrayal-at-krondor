#ifndef BAK_BOOT_H
#define BAK_BOOT_H

#include "structs.h"

extern int g_nEmsInit;
extern int g_nEmsResourcesEnabled;
extern unsigned short g_wEmmPagesFree;
extern char g_szVmcodeOvl[11];
extern unsigned short g_wTimerTickRegistrySlot;
extern short g_nWorldViewYawNormal;
extern short g_nWorldViewYawChapter;
extern short g_nWorldViewFovNormal;
extern unsigned char g_bssgap_4c53;
extern unsigned char g_nWorldViewFovChapter;

extern void boot_engine_exit(int exit_code);
extern void boot_party_state_load_from_temp(void);
extern void boot_party_state_save_to_temp(void);
extern void boot_audio_init(void);
extern void boot_sfx_resources_release(void);
extern void boot_video_init_for_mode(int mode);
extern void boot_engine_hardware_init(void);
extern void boot_engine_teardown_and_exit(void);
extern void boot_start_dat_load(void);
extern void boot_active_window_free(void);
extern void boot_check_memory_or_die(void);
extern void boot_startup_screen_show(void);
extern void boot_subsystems_init(void);
extern void boot_main_menu_resources_free(void);

#endif
