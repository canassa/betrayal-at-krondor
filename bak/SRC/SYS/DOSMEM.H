#ifndef BAK_DOSMEM_H
#define BAK_DOSMEM_H

/**
 * @file  DOSMEM.H
 * @brief Far (conventional-memory) allocator: thin wrappers over DOS INT 21h AH=48h/49h.
 *
 * @ref alloc_far reserves a paragraph-aligned block below 640K and hands back a
 * far pointer of the form segment:0000; @ref _freemem returns it to DOS. These
 * back the far/pool allocators in @c MEM.C (TBD-ref: MEM.C lacks a file block)
 * and @c POOL.C (TBD-ref: POOL.C lacks a file block).
 */

#include "structs.h"

/** @ref alloc_far flag requesting the returned block be zero-filled. */
#define ALLOC_FAR_ZERO_FILL 0x10000L

/**
 * @brief Allocate a paragraph-aligned far block from DOS conventional memory (INT 21h AH=48h).
 *
 * @details Rounds @p size up to whole 16-byte paragraphs and asks DOS for that
 *          many. Every block therefore begins at segment:0000, so a returned
 *          pointer can be treated as a flat segment base.
 *
 *          Passing @p size == 0xFFFFFFFF selects "query free memory" mode: the
 *          classic DOS idiom of requesting 0xFFFF paragraphs so the allocation
 *          deliberately fails, reads back the largest free block DOS reports,
 *          and returns that size as a byte count (paragraphs * 16) packed into
 *          the DX:AX far-pointer return. No memory is allocated in this mode.
 *
 * @param[in] size  Block size in bytes, rounded up to the next paragraph. The
 *                  sentinel 0xFFFFFFFF instead queries the largest free block
 *                  (see @details) and allocates nothing.
 * @param[in] flags Pass @ref ALLOC_FAR_ZERO_FILL to zero-fill the block; 0 (the
 *                  common case) leaves it uninitialized.
 * @return    Far pointer segment:0000 to the allocated block, or NULL on
 *            allocation failure. In query mode, the largest-free-block size in
 *            bytes reinterpreted as the far-pointer return value.
 */
extern void far *alloc_far(unsigned long size, long flags);

/**
 * @brief Release a block obtained from @ref alloc_far back to DOS (INT 21h AH=49h).
 *
 * @details Frees the memory block whose segment is the high word of the far
 *          pointer argument. The pointer must be one returned by @ref alloc_far
 *          (a segment:0000 block base), not an interior pointer.
 *
 * @return DOS status: 0 on success, otherwise the AH=49h error code (9 =
 *         invalid memory block address).
 */
extern int _freemem();

#endif
