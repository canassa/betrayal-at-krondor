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
 * Copyright (C) 2005-2007  Guido de Jong <guidoj@users.sf.net>
 */

#include <iomanip>
#include <iostream>

#include "SDL_endian.h"

#include "Defines.h"
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
FileBuffer::Copy(FileBuffer *buf, const unsigned int n)
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
    buf->GetData(buffer, MIN(size, buf->GetSize()));
  }
}

void
FileBuffer::Load(std::ifstream &ifs)
{
  if (ifs.is_open()) {
    current = buffer;
    ifs.read((char *)buffer, size);
    if (ifs.fail()) {
      throw IOError(__FILE__, __LINE__);
    }
  } else {
    throw OpenError(__FILE__, __LINE__);
  }
}

void
FileBuffer::Save(std::ofstream &ofs)
{
  if (ofs.is_open()) {
    current = buffer;
    ofs.write((char *)buffer, size);
    if (ofs.fail()) {
      throw IOError(__FILE__, __LINE__);
    }
  } else {
    throw OpenError(__FILE__, __LINE__);
  }
}

void
FileBuffer::Save(std::ofstream &ofs, const unsigned int n)
{
  if (ofs.is_open()) {
    if (n <= size) {
      current = buffer;
      ofs.write((char *)buffer, n);
      if (ofs.fail()) {
        throw IOError(__FILE__, __LINE__);
      }
    } else {
      throw BufferEmpty(__FILE__, __LINE__);
    }
  } else {
    throw OpenError(__FILE__, __LINE__);
  }
}

void
FileBuffer::Dump(const unsigned int n)
{
  uint8_t* tmp = current;
  unsigned int count = 0;
  std::cout << std::setbase(16) << std::setfill('0') << std::setw(8) << count << ": ";
  while ((tmp < (buffer + size)) && ((tmp < (current + n)) || (n == 0))) {
    std::cout << std::setw(2) << (unsigned int)*tmp++ << " ";
    if ((++count & 0x1f) == 0) {
      std::cout << std::endl << std::setw(8) << count << ": ";
    } else if ((count & 0x07) == 0) {
      std::cout << "| ";
    }
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
        unsigned int off = GetUint16LE();
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
      if ((GetUint8() != 0x02) || (GetUint32LE() != result->GetSize())) {
        throw DataCorruption(__FILE__, __LINE__); 
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
      throw CompressionError(__FILE__, __LINE__);
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
    throw BufferEmpty(__FILE__, __LINE__);
  }
  return 0;
}

uint16_t
FileBuffer::GetUint16LE()
{
  if ((current) && (current + 2 <= buffer + size)) {
    uint16_t n = 0;
    n = SDL_SwapLE16(*((uint16_t *)current));
    current += 2;
    return n;
  } else {
    throw BufferEmpty(__FILE__, __LINE__);
  }
  return 0;
}

uint16_t
FileBuffer::GetUint16BE()
{
  if ((current) && (current + 2 <= buffer + size)) {
    uint16_t n = 0;
    n = SDL_SwapBE16(*((uint16_t *)current));
    current += 2;
    return n;
  } else {
    throw BufferEmpty(__FILE__, __LINE__);
  }
  return 0;
}

uint32_t
FileBuffer::GetUint32LE()
{
  if ((current) && (current + 4 <= buffer + size)) {
    uint32_t n = 0;
    n = SDL_SwapLE32(*((uint32_t *)current));
    current += 4;
    return n;
  } else {
    throw BufferEmpty(__FILE__, __LINE__);
  }
  return 0;
}

uint32_t
FileBuffer::GetUint32BE()
{
  if ((current) && (current + 4 <= buffer + size)) {
    uint32_t n = 0;
    n = SDL_SwapBE32(*((uint32_t *)current));
    current += 4;
    return n;
  } else {
    throw BufferEmpty(__FILE__, __LINE__);
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
    throw BufferEmpty(__FILE__, __LINE__);
  }
  return 0;
}

int16_t
FileBuffer::GetSint16LE()
{
  if ((current) && (current + 2 <= buffer + size)) {
    int16_t n = 0;
    n = SDL_SwapLE16(*((uint16_t *)current));
    current += 2;
    return n;
  } else {
    throw BufferEmpty(__FILE__, __LINE__);
  }
  return 0;
}

int16_t
FileBuffer::GetSint16BE()
{
  if ((current) && (current + 2 <= buffer + size)) {
    int16_t n = 0;
    n = SDL_SwapBE16(*((uint16_t *)current));
    current += 2;
    return n;
  } else {
    throw BufferEmpty(__FILE__, __LINE__);
  }
  return 0;
}

int32_t
FileBuffer::GetSint32LE()
{
  if ((current) && (current + 4 <= buffer + size)) {
    int32_t n = 0;
    n = SDL_SwapLE32(*((uint32_t *)current));
    current += 4;
    return n;
  } else {
    throw BufferEmpty(__FILE__, __LINE__);
  }
  return 0;
}

int32_t
FileBuffer::GetSint32BE()
{
  if ((current) && (current + 4 <= buffer + size)) {
    int32_t n = 0;
    n = SDL_SwapBE32(*((uint32_t *)current));
    current += 4;
    return n;
  } else {
    throw BufferEmpty(__FILE__, __LINE__);
  }
  return 0;
}

std::string
FileBuffer::GetString()
{
  if (current) {
    std::string s((char *)current);
    if ((current + s.length() + 1) <= (buffer + size)) {
      current += s.length() + 1;
      return s;
    } else {
      throw BufferEmpty(__FILE__, __LINE__);
    }
  }
  return "";
}

std::string
FileBuffer::GetString(const unsigned int len)
{
  if ((current) && (current + len <= buffer + size)) {
    std::string s((char *)current);
    current += len;
    return s;
  } else {
    throw BufferEmpty(__FILE__, __LINE__);
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
    throw BufferEmpty(__FILE__, __LINE__);
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
    throw BufferEmpty(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutUint8(const uint8_t x)
{
  if ((current) && (current + 1 <= buffer + size)) {
    *((uint8_t *)current) = x;
    current += 1;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutUint16LE(const uint16_t x)
{
  if ((current) && (current + 2 <= buffer + size)) {
    *((uint16_t *)current) = SDL_SwapLE16(x);
    current += 2;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutUint16BE(const uint16_t x)
{
  if ((current) && (current + 2 <= buffer + size)) {
    *((uint16_t *)current) = SDL_SwapBE16(x);
    current += 2;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutUint32LE(const uint32_t x)
{
  if ((current) && (current + 4 <= buffer + size)) {
    *((uint32_t *)current) = SDL_SwapLE32(x);
    current += 4;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutUint32BE(const uint32_t x)
{
  if ((current) && (current + 4 <= buffer + size)) {
    *((uint32_t *)current) = SDL_SwapBE32(x);
    current += 4;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutSint8(const int8_t x)
{
  if ((current) && (current + 1 <= buffer + size)) {
    *((int8_t *)current) = x;
    current += 1;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutSint16LE(const int16_t x)
{
  if ((current) && (current + 2 <= buffer + size)) {
    *((uint16_t *)current) = SDL_SwapLE16(x);
    current += 2;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutSint16BE(const int16_t x)
{
  if ((current) && (current + 2 <= buffer + size)) {
    *((uint16_t *)current) = SDL_SwapBE16(x);
    current += 2;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutSint32LE(const int32_t x)
{
  if ((current) && (current + 4 <= buffer + size)) {
    *((uint32_t *)current) = SDL_SwapLE32(x);
    current += 4;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutSint32BE(const int32_t x)
{
  if ((current) && (current + 4 <= buffer + size)) {
    *((uint32_t *)current) = SDL_SwapBE32(x);
    current += 4;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutString(const std::string s)
{
  if ((current) && (current + s.length() + 1 <= buffer + size)) {
    strncpy((char *)current, s.c_str(), s.length() + 1);
    current += s.length() + 1;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutString(const std::string s, const unsigned int len)
{
  if ((current) && (current + len <= buffer + size)) {
    memset(current, 0, len);
    strncpy((char *)current, s.c_str(), len);
    current += len;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void
FileBuffer::PutData(void *data, const unsigned int n)
{
  if (current + n <= buffer + size) {
    memcpy(current, data, n);
    current += n;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}

void FileBuffer::PutData(const uint8_t x, const unsigned int n)
{
  if (current + n <= buffer + size) {
    memset(current, x, n);
    current += n;
  } else {
    throw BufferFull(__FILE__, __LINE__);
  }
}
