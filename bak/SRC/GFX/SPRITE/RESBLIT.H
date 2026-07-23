#ifndef BAK_RESBLIT_H
#define BAK_RESBLIT_H

#include "structs.h"

extern int g_nDialogScxEmsHandle;
extern int g_nInventorScxEmsHandle;
extern int g_nFrameScxEmsHandle;
extern ImageRecord **g_pHeadsBmxAssetTable;

extern void resblit_alloc_ems_64k(char *path, int *out_handle);
extern void resblit_load_resource_set_1ec(int flags);
extern ImageRecord **resblit_load_asset_table(char *path, int storage_mode);
extern void resblit_list_remap_palette(ResourceRemapDesc **resource_list, unsigned char *palette_lut);
extern void resblit_sprite(ImageRecord *sprite, int dst_x, int dst_y);
extern void resblit_sprite_frame(ImageRecord *sprite, int dst_x, int dst_y, int frame);
extern void resblit_hud_draw_party_icons_row(char *filename);
extern void resblit_load_pal_or_stream(char *filename);

#endif
