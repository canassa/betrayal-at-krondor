#ifndef BAK_AUDRES_H
#define BAK_AUDRES_H

#include "structs.h"

extern unsigned char far *audres_load_chunk_by_mode(BakFile *file, unsigned int size_lo, unsigned int size_hi,
                                            unsigned int *out_size, unsigned short codec_kind);
extern void audres_release_buffer_chain(AudFragNode far *head);
extern int audres_stream_find_tagged_record(int stream, unsigned char tag);
extern void far *audres_load_sorted_chain(int stream_id);
extern AudFragNode far *audres_sorted_list_insert(AudFragNode far *head, AudFragNode far *new_node);
extern int audres_resource_read_fragmented(int stream_id, AudFragNode far *fragment_list,
                                           unsigned char far *out_buf, int header_size, int tag);

#endif
