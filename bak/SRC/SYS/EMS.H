#ifndef BAK_EMS_H
#define BAK_EMS_H

#include "structs.h"

extern int g_ems_present;
extern unsigned short g_ems_total_pages;
extern unsigned short g_ems_free_pages;
extern unsigned short g_ems_frame_segment;
extern char s_ems_driver_signature[8];
extern unsigned short g_free_memory_kb;
extern unsigned short g_wEmsFreeListHead;
extern int *g_pEmsPageNextTbl;
extern int g_anEmsPageMap[8];

extern int ems_init(void);
extern unsigned short ems_get_free_memory(void);
extern void ems_shutdown(void);
extern int ems_alloc_pages(unsigned long size_bytes);
extern void ems_free_pages(int page_chain_1based);
extern unsigned char far *ems_map_at_offset(int page_chain_1based, long offset);
extern unsigned char far *ems_map_resource_pages(int page_id);

#endif
