#ifndef BAK_MAINMENU_H
#define BAK_MAINMENU_H

#include "structs.h"

extern int mainmenu_save_cfg_load_settings(void);
extern void mainmenu_save_cfg_free_settings(void);
extern int mainmenu_save_main_menu(int reentering);
extern int mainmenu_save_confirm_abort(void);
extern int mainmenu_save_load_game_dialog(void);
extern int mainmenu_save_save_game_dialog(void);
extern int mainmenu_save_prefs_menu_run(void);
extern int mainmenu_save_rmdir_recursive(char *dir_path);
extern int mainmenu_save_filename_validate(char *filename);
extern void mainmenu_save_show_ctrd_modal(void);
extern int mainmenu_save_games_dir_exists(void);
extern int mainmenu_save_games_dir_create(void);
extern int mainmenu_save_any_exists(void);
extern void mainmenu_save_bookmark(void);
extern void mainmenu_save_party_to_tmp(void);
extern int mainmenu_save_file_read_header(char *path, void *sig_block, int *ds_state_1,
                                          int *ds_state_2, int *ds_state_3, int *ds_state_4);
extern int mainmenu_save_scan_highest_slot(void);
extern int mainmenu_save_slot_is_at_cap(char *entry);
extern void mainmenu_save_slot_exists(void);
extern void mainmenu_save_request_load_game(void);
extern int mainmenu_save_enum_directories(ListWidget *list);
extern int mainmenu_save_parse_filename(char *filename, char *out_name, int *out_slot);
extern int mainmenu_save_enum_files_slot(ListWidget *list, char *slot_name, int slot_id);
extern int mainmenu_save_parse_read_title(char *title_buf, char *sig_block, int *out_save_id,
                                          char *slot_name, int slot_id, int *ds_state);
extern int mainmenu_savelist_insert_sorted(ListWidget *list, char *label, unsigned short key);
extern int mainmenu_savelist_nextfree_key(ListWidget *list);
extern int mainmenu_savelist_nextfree_nobm(ListWidget *list);
extern int mainmenu_savelist_find_by_text(ListWidget *list, char *text);
extern int mainmenu_savelist_find_by_name(ListWidget *list, char *name);

#endif
