#ifndef BAK_INVENTOR_H
#define BAK_INVENTOR_H

#include "structs.h"

extern void invui_inspect_image_cleanup(void);
extern void invui_inspect_images_load_once(int load_lock_images);
extern void invui_portrait_refresh_animated(int portrait_idx, int prev_portrait, int anim_step);
extern void invui_portr_panel_fill_pulsing(int state, int phase);
extern void invui_cur_spr_paint_ctrd(ImageRecord *sprite, int mode);
extern void invui_render_present_sync(MenuPage *page, Actor far *actor, short selected_slot,
                                      short highlight_slot);
extern int invui_handle_item_drag(MenuPage *page, Actor far *actor, int selected_slot,
                                  int *p_selected_slot);
extern void invui_draw_text_aligned_shadow(char far *text, int x, int y, int align, int fg_color,
                                           int shadow_color);
extern ImageRecord *invui_item_sprite_select(ItemSlot far *slot);
extern void invui_blit_spr_ckey_dflt_size(ImageRecord *sprite, int x, int y, int w, int h);
extern int invui_actor_inventory_kind(Actor far *actor, int flag);
extern void invui_status_icons_render(unsigned int status_bits, int x, int y);

#endif
