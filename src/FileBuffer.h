/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, GOOD TITLE or
 * NON INFRINGEMENT.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Copyright (C) 2005-2006  Guido de Jong <guidoj@users.sf.net>
 */

#ifndef FILE_BUFFER_H
#define FILE_BUFFER_H

#include <stdint.h>

#include <fstream>
#include <string>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

// try to determine endianness
#undef XBAK_LITTLE_ENDIAN
#undef XBAK_BIG_ENDIAN
#if (defined(__i386__) || defined(__i386)) || \
     defined(__ia64__) || defined(WIN32) || \
     defined(_WIN32) || defined(__WIN32__) || \
    (defined(__alpha__) || defined(__alpha)) || \
    (defined(__arm__) || defined(__thumb__)) || \
    (defined(__sh__) || defined(__sh64__)) || \
    (defined(__mips__) && defined(__MIPSEL__)) || \
     defined(__SYMBIAN32__) || defined(__x86_64__) || \
     defined(__OS2__) || defined(__LITTLE_ENDIAN__)
#define XBAK_LITTLE_ENDIAN
#else
#define XBAK_BIG_ENDIAN
#endif

static const unsigned int COMPRESSION_LZW = 0;
static const unsigned int COMPRESSION_LZ = 1;
static const unsigned int COMPRESSION_RLE = 2;

class FileBuffer {
  private:
    uint8_t * buffer;
    uint8_t * current;
    unsigned int size;
    unsigned int nextbit;
  public:
    FileBuffer(const unsigned int n);
    virtual ~FileBuffer();

    void Load(std::ifstream &ifs);
    void Save(std::ofstream &ofs);
    void Dump();
    void Copy(FileBuffer *buf, unsigned int n); 
    void Fill(FileBuffer *buf);
    void Rewind();
    void Seek(const unsigned int n);
    void Skip(const int n);

    void SkipBits();
    void DecompressLZW(FileBuffer *result);
    void DecompressLZ(FileBuffer *result);
    void DecompressRLE(FileBuffer *result);
    void Decompress(FileBuffer *result, const unsigned int method);

    bool AtEnd() const;
    unsigned int GetSize() const;
    unsigned int GetBytesDone() const;
    unsigned int GetBytesLeft() const;
    uint8_t * GetCurrent() const;
    unsigned int GetNextBit() const;

    uint8_t GetUint8();
    uint16_t GetUint16();
    uint32_t GetUint32();
    int8_t GetSint8();
    int16_t GetSint16();
    int32_t GetSint32();
    std::string GetString();
    std::string GetString(const unsigned int len);
    void GetData(void * data, const unsigned int n);
    unsigned int GetBits(const unsigned int n);

    void PutUint8(const uint8_t x);
    void PutUint16(const uint16_t x);
    void PutUint32(const uint32_t x);
    void PutSint8(const int8_t x);
    void PutSint16(const int16_t x);
    void PutSint32(const int32_t x);
    void PutString(const std::string s);
    void PutData(void * data, const unsigned int n);
    void PutData(const uint8_t x, const unsigned int n);
};

#endif

