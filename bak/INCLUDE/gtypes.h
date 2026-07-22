/**
 * @file  gtypes.h
 * @brief Core boolean primitives: the @ref TRUE / @ref FALSE constants and
 *        the @ref bool8 / @ref bool16 types.
 */
#ifndef BAK_GTYPES_H
#define BAK_GTYPES_H

/** @brief Boolean true value (1). */
#define TRUE 1
/** @brief Boolean false value (0). */
#define FALSE 0

/** @brief 8-bit boolean; assign only @ref TRUE or @ref FALSE. */
typedef char bool8;
/** @brief 16-bit (int-width) boolean; assign only @ref TRUE or @ref FALSE. */
typedef int bool16;

typedef void code;

#endif
