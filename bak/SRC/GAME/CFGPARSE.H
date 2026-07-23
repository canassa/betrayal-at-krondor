/**
 * @file  CFGPARSE.H
 * @brief The `g_cfg` settings globals and the config parser that fills them.
 */
#ifndef BAK_CFGPARSE_H
#define BAK_CFGPARSE_H

#include "gtypes.h"

/**
 * @brief Cheat-menu unlock flag, read by the 3-D world view.
 *
 * FALSE on a stock install; set TRUE only when `resource.cfg` carries a
 * `knockknock` line whose argument is exactly 29 characters. While TRUE,
 * the RShift+Alt+tilde chord opens the hidden cheat menu.
 */
extern bool16 g_cfgKnockKnock;

/**
 * @brief Value of the undocumented `cycle` config key — dead, never read.
 *
 * Parsed from a `cycle` line in `resource.cfg` into this global, which has no
 * reader anywhere in the game.
 */
extern int g_cfgCycle;

/**
 * @brief Drive letter for the `TEMP.GAM` swap file (0 = current drive).
 *
 * Set from the `tempdrive` line in `resource.cfg` (its first character,
 * upper-cased). When non-zero the swap path is drive-relative `D:TEMP.GAM`;
 * when 0 (the default) the file is the bare `TEMP.GAM` on the current drive.
 */
extern int g_cfgTempDrive;

/**
 * @brief Bookmark-overwrite confirmation flag.
 *
 * TRUE by default; set from the `bookmarkverify` line in `resource.cfg`.
 * While TRUE, saving a bookmark first prompts to confirm before it
 * overwrites the existing one; while FALSE the save is silent.
 */
extern bool16 g_cfgBookmarkVerify;

#ifdef V102CD
/**
 * @brief Drive prefix (`<letter>:`) for the resource-archive opens (1.02 CD).
 *
 * Points at a mutable 3-byte `"x:"` buffer whose first byte is overwritten
 * with line 1 of the installer-written `drive.cfg` — the drive holding
 * `krondor.rmf` and `krondor.001`: the hard drive on a full install, the CD
 * drive on a partial one. Prepending it yields drive-relative paths
 * (`C:krondor.rmf`); it is a drive prefix, never a directory.
 */
extern char *g_cfgResourceDrivePrefix;

/**
 * @brief Drive letter probed as the CD-audio source (1.02 CD).
 *
 * Line 2 of `drive.cfg`, passed once to the MSCDEX drive check at boot. A
 * partial install deliberately carries the hard-drive letter here, so the
 * check fails and CD music stays off.
 */
extern char g_cfgCdDriveLetter;

/**
 * @brief Fixed-orientation overhead map flag (1.02 CD only).
 *
 * FALSE keeps the 1.00 behavior: the close overhead map rotates so the
 * party's heading is always screen-up, with a static up-arrow as the party
 * marker. TRUE renders the map in a fixed orientation.
 */
extern bool16 g_cfgNonRotatingMap;
#endif

/**
 * @brief Parse `resource.cfg` and populate the `g_cfg` settings globals.
 *
 * Reads `resource.cfg` from the current directory at boot and applies each
 * recognized setting to its global. On the 1.02 CD build it then also reads
 * the installer-written `drive.cfg` (see below). The rest of the shipped
 * `resource.cfg` — the installer's minimum-requirement and hardware lines —
 * is silently ignored by the game.
 *
 * @par File format
 * `resource.cfg` is a flat, whitespace-delimited token stream: keys and their
 * values are simply tokens separated by any run of spaces, tabs, or newlines
 * (the parser reads with `fscanf(" %40s")`, so line structure is irrelevant).
 * Each recognized key is followed by two more tokens: a separator and the
 * value. The shipped files write the separator as `=`, but the parser accepts
 * *any* single token there and discards it — `key value` works as well as
 * `key = value`. Key matching is case-insensitive.
 *
 * A token that matches no known key is skipped, and the scan resumes at the
 * next token. This is why the installer-oriented lines (`minEMS`, `minCPU`,
 * `minDOS`, `mouseDrv`, `memoryDrv`, `joyDrv`, `size`, `cd`, ...) coexist
 * harmlessly with the game's parser: their key tokens, their `=` separators,
 * and their value tokens all fall through the unknown-token path and re-enter
 * the key scan on the next read.
 *
 * @par Example
 * A representative full-install `resource.cfg` (1.00). Only `soundDrv` and
 * `knockknock` are read by the game; every other line is skipped:
 * @code{.unparsed}
 *  soundDrv  = MT32.DRV
 *  mouseDrv = none
 *  memoryDrv = none
 *  joyDrv    = none
 *      minEMS = 1024
 *      minCPU = 386
 *      minDOS = 500
 *      size = 15000
 *  knockknock = <29-character unlock string>
 * @endcode
 *
 * @par Recognized keys
 * - `sounddrv` — value matched case-insensitively against
 *   @ref g_soundDrvTokens; a hit selects the parallel entry of
 *   @ref g_soundDrvIds as the active sound driver.
 * - `knockknock` — sets @ref g_cfgKnockKnock TRUE only when the value token is
 *   exactly 29 characters long (the cheat-menu unlock string).
 * - `cycle` — parsed with `atoi` into @ref g_cfgCycle, which no reader ever
 *   consults (dead setting).
 * - `tempdrive` — takes the value's first character, upper-cased, into
 *   @ref g_cfgTempDrive, but only when that character is alphabetic.
 * - `bookmarkverify` — `atoi` of the value into @ref g_cfgBookmarkVerify.
 * - `NonRotatingMap` — 1.02 CD only; `atoi` of the value into
 *   @ref g_cfgNonRotatingMap.
 *
 * @par drive.cfg (1.02 CD only)
 * After finishing `resource.cfg`, the CD build reads the two-line
 * installer-written `drive.cfg`: line 1's first byte becomes the resource
 * drive prefix @ref g_cfgResourceDrivePrefix and line 2's first byte becomes
 * @ref g_cfgCdDriveLetter. The meaning of those bytes is documented on the
 * globals themselves.
 *
 * @note Value tokens of ignored keys re-enter the key scan on the following
 *       read, so a value that happens to spell a game key would be matched as
 *       one. In the shipped files this never occurs — no ignored value
 *       (`none`, `1024`, `386`, `500`, `15000`, `yes`) collides with a
 *       recognized key.
 * @note Tokens are capped at 40 characters by the `%40s` field width; the loop
 *       runs until `fscanf` returns EOF.
 * @warning The `fopen` results are not checked. A missing `resource.cfg`
 *          (and, on the CD build, a missing `drive.cfg`) leaves `fp` NULL and
 *          `fscanf` is called on it regardless.
 */
extern void parse_krondor_cfg(void);

#endif
