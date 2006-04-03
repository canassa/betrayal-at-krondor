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

#include "Exception.h"
#include "BookResource.h"

BookResource::BookResource()
{
}

BookResource::~BookResource()
{
}

void
BookResource::Load(FileBuffer *buffer)
{
  try {
    printf("%d\n", buffer->GetUint32());
    unsigned int n;
    n = buffer->GetUint16();
    printf("%d\n", n);
    for (unsigned int i = 0; i < n; i++) {
      printf("%d ", buffer->GetUint32());
    }
    printf("\n");
    for (unsigned int i = 0; i < 40; i++) {
      printf("%04x ", buffer->GetUint16());
    }
    unsigned int code = buffer->GetUint8();
    while (code != 0xf0) {
      switch (code) {
        case 0xf1:
          printf("\n");
          for (unsigned int i = 0; i < 8; i++) {
            printf("%d ", buffer->GetSint16());
          }
          printf("\n");
          break;
        case 0xf4:
          for (unsigned int i = 0; i < 5; i++) {
            printf("%d ", buffer->GetSint16());
          }
          printf("\n");
          break;
        default:
          printf("%c", (char)code);
          break;
      }
      code = buffer->GetUint8();
    }
    printf("\n");
    code = buffer->GetUint8();
    buffer->Skip(-1);
    while (code != 0xf0) {
      printf("%04x ", buffer->GetUint16());
      code = buffer->GetUint8();
      buffer->Skip(-1);
    }
    printf("\n");
    while (code != 0xf0) {
      printf("%04x ", buffer->GetUint16());
      code = buffer->GetUint8();
      buffer->Skip(-1);
    }
    printf("\n");
  } catch (Exception &e) {
    e.Print("BookResource::Load");
  }
}
