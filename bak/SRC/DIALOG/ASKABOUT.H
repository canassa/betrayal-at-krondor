#ifndef BAK_ASKABOUT_H
#define BAK_ASKABOUT_H

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

#endif
