/**
 * @file    RESFAR.H
 * @brief   Far-memory transfers over the near-only resource-I/O layer.
 */
#ifndef BAK_RESFAR_H
#define BAK_RESFAR_H

#include "SRC/IO/RESOURCE.H"


/**
 * @brief Read from a resource stream, `fread`-style, into far memory.
 *
 * Far-buffer counterpart of @ref res_fread, for destinations the near `void *`
 * of the resource layer cannot address; moves `size * count` bytes.
 *
 * @param dest Destination anywhere in far memory; must have room for
 *             `size * count` bytes.
 * @return @p count, unconditionally — short reads are not detected.
 */
extern long res_fread_far(void huge *dest, long size, long count, ResFile *file);


/**
 * @brief Write to a resource stream, `fwrite`-style, from far memory.
 *
 * Far-buffer counterpart of @ref res_fwrite, for sources the near `void *` of
 * the resource layer cannot address; moves `size * count` bytes.
 *
 * @param src Source anywhere in far memory.
 * @return `0`, unconditionally — short writes are not detected.
 */
extern long res_fwrite_far(void huge *src, long size, long count, ResFile *file);

#endif
