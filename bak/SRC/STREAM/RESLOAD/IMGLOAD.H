#ifndef BAK_IMGLOAD_H
#define BAK_IMGLOAD_H

#include "structs.h"

extern int iff_chunk_loader_2f1c(BakFile *file, ushort *count, ushort *out_handle);
extern ushort bak_load_image_record_chunked(BakFileRef *fname);
extern void free_container_pair(int *container);
extern void free_image_record(ImageRecord **record);
extern int null_terminated_count(ImageRecord **table);
extern void unpack_2bpp_to_byte_per_pixel(uchar huge *src, uchar huge *dst, unsigned count);

#endif
