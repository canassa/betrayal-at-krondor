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

#include "AnimationResource.h"
#include "Exception.h"
#include "ResourceTag.h"

AnimationResource::AnimationResource()
: TaggedResource()
, version("")
, animationMap()
, script(0)
{
}

AnimationResource::~AnimationResource()
{
  animationMap.clear();
  if (script) {
    delete script;
  }
}

std::string&
AnimationResource::GetVersion()
{
  return version;
}

FileBuffer *
AnimationResource::GetScript() const
{
  return script;
}

AnimationData&
AnimationResource::GetAnimationData(unsigned int id)
{
  return animationMap[id];
}

void
AnimationResource::Load(FileBuffer *buffer)
{
  try {
    Split(buffer);
    FileBuffer *verbuf;
    FileBuffer *resbuf;
    FileBuffer *scrbuf;
    FileBuffer *tagbuf;
    if (!Find(TAG_VER, verbuf) ||
        !Find(TAG_RES, resbuf) ||
        !Find(TAG_SCR, scrbuf) ||
        !Find(TAG_TAG, tagbuf)) {
      Clear();
      throw DataCorruption("AnimationResource::Load");
    }
    version = verbuf->GetString();
    if (scrbuf->GetUint8() != 0x02) {
      Clear();
      throw DataCorruption("AnimationResource::Load");
    }
    script = new FileBuffer(scrbuf->GetUint32());
    scrbuf->DecompressLZW(script);
    ResourceTag tags;
    tags.Load(tagbuf);
    unsigned int n = resbuf->GetUint16();
    for (unsigned int i = 0; i < n; i++) {
      unsigned int id = resbuf->GetUint16();
      std::string resource = resbuf->GetString();
      std::string name;
      if (tags.Find(id, name)) {
        AnimationData data;
        data.name = name;
        data.resource = resource;
        animationMap.insert(std::pair<unsigned int, AnimationData>(id, data));
      } else {
        throw DataCorruption("AnimationResource::Load");
      }
    }
    Clear();
  } catch (Exception &e) {
    e.Print("AnimationResource::Load");
    Clear();
  }
}

