#ifndef BAK_TOWNSCN_H
#define BAK_TOWNSCN_H

#include "structs.h"

extern void townscene_main_loop(unsigned int scene_kind, int scene_index);
extern void townscene_anim_channel_play_sync(int channel_id);
extern void townscene_cheat_menu_screen(void);
extern void townscene_chest_open_with_cipher(void);

#endif
