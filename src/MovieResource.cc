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

#include <algorithm>
#include <cctype>

#include "Exception.h"
#include "ResourceTag.h"
#include "MovieResource.h"

MovieResource::MovieResource()
: TaggedResource()
, version("")
, pages(0)
, movieTags()
{
}

MovieResource::~MovieResource()
{
  for (unsigned int i = 0; i < movieTags.size(); i++) {
    movieTags[i]->data.clear();
    delete movieTags[i];
  }
  movieTags.clear();
}

std::string&
MovieResource::GetVersion()
{
  return version;
}

unsigned int
MovieResource::GetPages() const
{
  return pages;
}

std::vector<MovieTag *> &
MovieResource::GetMovieTags()
{
  return movieTags;
}

void
MovieResource::Load(FileBuffer *buffer)
{
  try {
    Split(buffer);
    FileBuffer *verbuf;
    FileBuffer *pagbuf;
    FileBuffer *tt3buf;
    FileBuffer *tagbuf;
    if (!Find(TAG_VER, verbuf) ||
        !Find(TAG_PAG, pagbuf) ||
        !Find(TAG_TT3, tt3buf) ||
        !Find(TAG_TAG, tagbuf)) {
      Clear();
      throw DataCorruption(__FILE__, __LINE__);
    }
    version = verbuf->GetString();
    pages = pagbuf->GetUint16LE();
    tt3buf->Skip(1);
    FileBuffer *tmpbuf = new FileBuffer(tt3buf->GetUint32LE());
    tt3buf->DecompressRLE(tmpbuf);
    ResourceTag tags;
    tags.Load(tagbuf);
    while (!tmpbuf->AtEnd()) {
      MovieTag *mt = new MovieTag;
      unsigned int code = tmpbuf->GetUint16LE();
      unsigned int size = code & 0x000f;
      code &= 0xfff0;
      mt->code = code;
      if ((code == 0x1110) && (size == 1)) {
        unsigned int id = tmpbuf->GetUint16LE();
        mt->data.push_back(id);
        std::string name;
        if (tags.Find(id, name)) {
          mt->name = name;
        } 
      } else if (size == 15) {
        mt->name = tmpbuf->GetString();
        transform(mt->name.begin(), mt->name.end(), mt->name.begin(), toupper);
        if (tmpbuf->GetBytesLeft() & 1) {
          tmpbuf->Skip(1);
        }
      } else {
        for (unsigned int i = 0; i < size; i++) {
          mt->data.push_back(tmpbuf->GetSint16LE());
        }
      }
      movieTags.push_back(mt);
    }
    delete tmpbuf;
    Clear();
  } catch (Exception &e) {
    e.Print("MovieResource::Load");
    Clear();
  }
}

