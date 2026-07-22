#ifndef BAK_EMS_H
#define BAK_EMS_H

#include "structs.h"

extern int ems_init(void);
extern unsigned short ems_get_free_memory(void);
extern void ems_shutdown(void);
extern int ems_alloc_pages(unsigned long size_bytes);
extern void ems_free_pages(int page_chain_1based);
extern unsigned char far *ems_map_at_offset(int page_chain_1based, long offset);
extern unsigned char far *ems_map_resource_pages(int page_id);

#endif
