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

#include <iomanip>
#include <iostream>

#include "Exception.h"
#include "FileBuffer.h"

FileBuffer::FileBuffer(const unsigned int n)
{
  buffer = new uint8_t[n];
  memset(buffer, 0, n);
  current = buffer;
  size = n;
  nextbit = 0;
}

FileBuffer::~FileBuffer()
{
  if (buffer) {
    delete[] buffer;
  }
}

void
FileBuffer::Copy(FileBuffer *buf, unsigned int n)
{
  if (buffer && n && (current + n <= buffer + size)) {
    buf->GetData(current, n);
    current += n;
  }
}

void
FileBuffer::Fill(FileBuffer *buf)
{
  if (buffer) {
    current = buffer;
    buf->GetData(buffer, (size <= buf->GetSize() ? size : buf->GetSize()));
  }
}

void
FileBuffer::Load(std::ifstream &ifs)
{
  if (ifs.is_open()) {
    current = buffer;
    ifs.read((char *)buffer, size);
    if (ifs.fail()) {
      throw IOError("FileBuffer::Load");
    }
  } else {
    throw OpenError("FileBuffer::Load");
  }
}

void
FileBuffer::Save(std::ofstream &ofs)
{
  if (ofs.is_open()) {
    current = buffer;
    ofs.write((char *)buffer, size);
    if (ofs.fail()) {
      throw IOError("FileBuffer::Save");
    }
  } else {
    throw OpenError("FileBuffer::Save");
  }
}

void
FileBuffer::Dump()
{
  current = buffer;
  std::cout << std::setbase(16) << std::setfill('0');
  while (current < (buffer + size)) {
    std::cout << std::setw(2) << (unsigned int)*current++ << " ";
  }
  std::cout << std::endl;
}

void
FileBuffer::Seek(const unsigned int n)
{
  if ((current) && (n <= size)) {
    current = buffer + n;
  }
}

void
FileBuffer::Skip(const int n)
{
  if ((current) && (current + n <= buffer + size)) {
    current += n;
  }
}

void
FileBuffer::SkipBits()
{
  if (nextbit) {
    Skip(1);
    nextbit = 0;
  }
}

typedef struct _CodeTableEntry {
  uint16_t prefix;
  uint8_t  append;
} CodeTableEntry;

void
FileBuffer::DecompressLZW(FileBuffer *result)
{
  try {
    CodeTableEntry *codetable = new CodeTableEntry[4096];
    uint8_t *decodestack = new uint8_t[4096];
    uint8_t *stackptr = decodestack;
    unsigned int n_bits = 9;
    unsigned int free_entry = 257;
    unsigned int oldcode = GetBits(n_bits);
    unsigned int lastbyte = oldcode;
    unsigned int bitpos = 0;
    result->PutUint8(oldcode);
    while (!AtEnd() && !result->AtEnd()) {
      unsigned int newcode = GetBits(n_bits);
      bitpos += n_bits;
      if (newcode == 256) {
        SkipBits(); 
        Skip((((bitpos-1)+((n_bits<<3)-(bitpos-1+(n_bits<<3))%(n_bits<<3)))-bitpos)>>3);
        n_bits = 9;
        free_entry = 256;
        bitpos = 0;
      } else { 
        unsigned int code = newcode;
        if (code >= free_entry) {
          *stackptr++ = lastbyte;
          code = oldcode;
        }
        while (code >= 256) {
          *stackptr++ = codetable[code].append;
          code = codetable[code].prefix;
        }
        *stackptr++ = code;
        lastbyte = code;
        while (stackptr > decodestack) {
          result->PutUint8(*--stackptr);
        }
        if (free_entry < 4096) {
          codetable[free_entry].prefix = oldcode;
          codetable[free_entry].append = lastbyte;
          free_entry++;
          if ((free_entry >= (unsigned int)(1 << n_bits)) && (n_bits < 12)) {
            n_bits++;
            bitpos = 0;
          }
        }
        oldcode = newcode;
      }
    }
    delete[] decodestack;
    delete[] codetable;
    result->Rewind();
  } catch (Exception &e) {
    e.Print("FileBuffer::DecompressLZW");
  }
}

void
FileBuffer::DecompressLZ(FileBuffer *result)
{
  try {
    uint8_t *data = result->GetCurrent();
    uint8_t code = 0;
    uint8_t mask = 0;
    while (!AtEnd() && !result->AtEnd()) {
      if (!mask) {
        code = GetUint8();
        mask = 0x01;
      }
      if (code & mask) {
        result->PutUint8(GetUint8());
      } else {
        unsigned int off = GetUint16();
        unsigned int len = GetUint8() + 5;
        result->PutData(data + off, len);
      }
      mask <<= 1;
    }
    result->Rewind();
  } catch (Exception &e) {
    e.Print("FileBuffer::DecompressLZ");
  }
}

void
FileBuffer::DecompressRLE(FileBuffer *result)
{
  try {
    while (!AtEnd() && !result->AtEnd()) {
      uint8_t control = GetUint8();
      if (control & 0x80) {
        result->PutData(GetUint8(), control & 0x7f);
      } else {
        result->Copy(this, control);
      }
    }
    result->Rewind();
  } catch (Exception &e) {
    e.Print("FileBuffer::DecompressRLE");
  }
}

void
FileBuffer::Decompress(FileBuffer *result, const unsigned int method)
{
  switch (method) {
    case COMPRESSION_LZW:
      if ((GetUint8() != 0x02) || (GetUint32() != result->GetSize())) {
        throw DataCorruption("FileBuffer::Decompress"); 
      } 
      DecompressLZW(result);
      break;
    case COMPRESSION_LZ:
      DecompressLZ(result);
      break;
    case COMPRESSION_RLE:
      DecompressRLE(result);
      break;
    default:
      throw CompressionError("FileBuffer::Decompress");
      break;
  }
}

bool
FileBuffer::AtEnd() const
{
  return (current >= buffer + size);
}

unsigned int
FileBuffer::GetSize() const
{
  return size;
}

unsigned int
FileBuffer::GetBytesDone() const
{
  return (current - buffer);
}

unsigned int
FileBuffer::GetBytesLeft() const
{
  return (buffer + size - current);
}

uint8_t *
FileBuffer::GetCurrent() const
{
  return current;
}

unsigned int
FileBuffer::GetNextBit() const
{
  return nextbit;
}

void
FileBuffer::Rewind()
{
  current = buffer;
}

uint8_t
FileBuffer::GetUint8()
{
  if ((current) && (current + 1 <= buffer + size)) {
    uint8_t n = 0;
    n = *((uint8_t *)current);
    current += 1;
    return n;
  } else {
    throw BufferEmpty("FileBuffer::GetUint8");
  }
  return 0;
}

uint16_t
FileBuffer::GetUint16()
{
  if ((current) && (current + 2 <= buffer + size)) {
    uint16_t n = 0;
#ifdef XBAK_LITTLE_ENDIAN
    n = *((uint16_t *)current);
#else
    n = ((uint8_t *)current)[0] << 8 | ((uint8_t *)current)[1];
#endif
    current += 2;
    return n;
  } else {
    throw BufferEmpty("FileBuffer::GetUint16");
  }
  return 0;
}

uint32_t
FileBuffer::GetUint32()
{
  if ((current) && (current + 4 <= buffer + size)) {
    uint32_t n = 0;
#ifdef XBAK_LITTLE_ENDIAN
    n = *((uint32_t *)current);
#else
    n = ((uint8_t *)current)[0] << 24 | ((uint8_t *)current)[1] << 16 | ((uint8_t *)current)[2] << 8 | ((uint8_t *)current)[3];
#endif
    current += 4;
    return n;
  } else {
    throw BufferEmpty("FileBuffer::GetUint32");
  }
  return 0;
}

int8_t
FileBuffer::GetSint8()
{
  if ((current) && (current + 1 <= buffer + size)) {
    int8_t n = 0;
    n = *((int8_t *)current);
    current += 1;
    return n;
  } else {
    throw BufferEmpty("FileBuffer::GetSint8");
  }
  return 0;
}

int16_t
FileBuffer::GetSint16()
{
  if ((current) && (current + 2 <= buffer + size)) {
    int16_t n = 0;
#ifdef XBAK_LITTLE_ENDIAN
    n = *((int16_t *)current);
#else
    n = ((int8_t *)current)[0] << 8 | ((int8_t *)current)[1];
#endif
    current += 2;
    return n;
  } else {
    throw BufferEmpty("FileBuffer::GetSint16");
  }
  return 0;
}

int32_t
FileBuffer::GetSint32()
{
  if ((current) && (current + 4 <= buffer + size)) {
    int32_t n = 0;
#ifdef XBAK_LITTLE_ENDIAN
    n = *((int32_t *)current);
#else
    n = ((int8_t *)current)[0] << 24 | ((int8_t *)current)[1] << 16 | ((int8_t *)current)[2] << 8 | ((int8_t *)current)[3];
#endif
    current += 4;
    return n;
  } else {
    throw BufferEmpty("FileBuffer::GetSint32");
  }
  return 0;
}

std::string
FileBuffer::GetString()
{
  std::string s;
  if (current) {
    s = std::string((char *)current);
  }
  if ((current) && (current + s.length() + 1) <= (buffer + size)) {
    current += s.length() + 1;
    return s;
  } else {
    throw BufferEmpty("FileBuffer::GetString");
  }
  return "";
}

std::string
FileBuffer::GetString(const unsigned int len)
{
  if ((current) && (current + len <= buffer + size)) {
    std::string s = std::string((char *)current);
    current += len;
    return s;
  } else {
    throw BufferEmpty("FileBuffer::GetString");
  }
  return "";
}

void
FileBuffer::GetData(void *data,
                    const unsigned int n)
{
  if (current + n <= buffer + size) {
    memcpy(data, current, n);
    current += n;
  } else {
    throw BufferEmpty("FileBuffer::GetData");
  }
}

unsigned int
FileBuffer::GetBits(const unsigned int n)
{
  if (current + ((nextbit + n + 7)/8) <= buffer + size) {
    unsigned int x = 0;
    for (unsigned int i = 0; i < n; i++) {
      if (*current & (1 << nextbit)) {
        x += (1 << i);
      }
      nextbit++;
      if (nextbit > 7) {
        current++;
        nextbit = 0;
      }
    }
    return x;
  } else {
    throw BufferEmpty("FileBuffer::GetBits");
  }
}

void
FileBuffer::PutUint8(const uint8_t x)
{
  if ((current) && (current + 1 <= buffer + size)) {
    *((uint8_t *)current) = x;
    current += 1;
  } else {
    throw BufferFull("FileBuffer::PutUint8");
  }
}

void
FileBuffer::PutUint16(const uint16_t x)
{
  if ((current) && (current + 2 <= buffer + size)) {
#ifdef XBAK_LITTLE_ENDIAN
    *((uint16_t *)current) = x;
#else
    ((uint8_t *)current)[0] = (x >> 8) & 0xff;
    ((uint8_t *)current)[1] = x & 0xff;
#endif
    current += 2;
  } else {
    throw BufferFull("FileBuffer::PutUint16");
  }
}

void
FileBuffer::PutUint32(const uint32_t x)
{
  if ((current) && (current + 4 <= buffer + size)) {
#ifdef XBAK_LITTLE_ENDIAN
    *((uint32_t *)current) = x;
#else
    ((uint8_t *)current)[0] = (x >> 24) & 0xff;
    ((uint8_t *)current)[1] = (x >> 16) & 0xff;
    ((uint8_t *)current)[2] = (x >> 8) & 0xff;
    ((uint8_t *)current)[3] = x & 0xff;
#endif
    current += 4;
  } else {
    throw BufferFull("FileBuffer::PutUint32");
  }
}

void
FileBuffer::PutSint8(const int8_t x)
{
  if ((current) && (current + 1 <= buffer + size)) {
    *((int8_t *)current) = x;
    current += 1;
  } else {
    throw BufferFull("FileBuffer::PutSint8");
  }
}

void
FileBuffer::PutSint16(const int16_t x)
{
  if ((current) && (current + 2 <= buffer + size)) {
#ifdef XBAK_LITTLE_ENDIAN
    *((int16_t *)current) = x;
#else
    ((int8_t *)current)[0] = (x >> 8) & 0xff;
    ((int8_t *)current)[1] = x & 0xff;
#endif
    current += 2;
  } else {
    throw BufferFull("FileBuffer::PutSint16");
  }
}

void
FileBuffer::PutSint32(const int32_t x)
{
  if ((current) && (current + 4 <= buffer + size)) {
#ifdef XBAK_LITTLE_ENDIAN
    *((int32_t *)current) = x;
#else
    ((int8_t *)current)[0] = (x >> 24) & 0xff;
    ((int8_t *)current)[1] = (x >> 16) & 0xff;
    ((int8_t *)current)[2] = (x >> 8) & 0xff;
    ((int8_t *)current)[3] = x & 0xff;
#endif
    current += 4;
  } else {
    throw BufferFull("FileBuffer::PutSint32");
  }
}

void
FileBuffer::PutString(const std::string s)
{
  if ((current) && (current + s.length() + 1 <= buffer + size)) {
    memcpy(current, s.data(), s.length());
    current += s.length();
    *current++ = 0;
  } else {
    throw BufferFull("FileBuffer::PutString");
  }
}

void
FileBuffer::PutData(void *data, const unsigned int n)
{
  if (current + n <= buffer + size) {
    memcpy(current, data, n);
    current += n;
  } else {
    throw BufferFull("FileBuffer::PutData");
  }
}

void FileBuffer::PutData(const uint8_t x, const unsigned int n)
{
  if (current + n <= buffer + size) {
    memset(current, x, n);
    current += n;
  } else {
    throw BufferFull("FileBuffer::PutData");
  }
}

