#ifndef BAK_AUDRES_H
#define BAK_AUDRES_H

#include "structs.h"

extern uchar far *audres_load_chunk_by_mode(BakFile *file, uint size_lo, uint size_hi,
                                            uint *out_size, ushort codec_kind);
extern void audres_release_buffer_chain(AudFragNode far *head);
extern int audres_stream_find_tagged_record(int stream, unsigned char tag);
extern void far *audres_load_sorted_chain(int stream_id);
extern AudFragNode far *audres_sorted_list_insert(AudFragNode far *head, AudFragNode far *new_node);
extern int audres_resource_read_fragmented(int stream_id, AudFragNode far *fragment_list,
                                           uchar far *out_buf, int header_size, int tag);

#endif
