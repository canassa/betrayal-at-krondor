/**
 * @file    DOSRW.H
 * @brief   Raw chunked DOS file I/O over a DOS handle (INT 21h AH=3Fh/40h).
 *
 * Thin wrappers, implemented in `DOSRW.ASM`, that transfer up to a `long` byte
 * count in <=0x7FFF-byte chunks (DOS cannot do a single >64 KB transfer) through
 * a raw DOS file descriptor — bypassing the CRT and the resource layer. Used by
 * the save-game file copier.
 */
#ifndef BAK_DOSRW_H
#define BAK_DOSRW_H

/**
 * @brief Read up to @p count bytes from DOS handle @p fd into @p buf
 *        (INT 21h AH=3Fh), chunked for transfers over 64 KB.
 * @param buf   Far destination buffer.
 * @param count Byte count to read.
 * @param fd    Open DOS file handle.
 * @return Bytes actually read, or 0 on error.
 */
extern long far dos_read(unsigned char far *buf, long count, int fd);

/**
 * @brief Write up to @p count bytes from @p buf to DOS handle @p fd
 *        (INT 21h AH=40h), chunked for transfers over 64 KB.
 * @param buf   Far source buffer.
 * @param count Byte count to write.
 * @param fd    Open DOS file handle.
 * @return Bytes actually written, or 0 on error.
 */
extern long far dos_write(unsigned char far *buf, long count, int fd);

#endif
