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

#ifndef TAGGED_RESOURCE_H
#define TAGGED_RESOURCE_H

#include <map>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "ResourceData.h"

static const uint32_t TAG_ADS = 0x3a534441;
static const uint32_t TAG_APP = 0x3a505041;
static const uint32_t TAG_BIN = 0x3a4e4942;
static const uint32_t TAG_BMP = 0x3a504d42;
static const uint32_t TAG_DAT = 0x3a544144;
static const uint32_t TAG_FNT = 0x3a544e46;
static const uint32_t TAG_GID = 0x3a444947;
static const uint32_t TAG_INF = 0x3a464e49;
static const uint32_t TAG_MAP = 0x3a50414d;
static const uint32_t TAG_PAG = 0x3a474150;
static const uint32_t TAG_PAL = 0x3a4c4150;
static const uint32_t TAG_RES = 0x3a534552;
static const uint32_t TAG_SCR = 0x3a524353;
static const uint32_t TAG_SND = 0x3a444e53;
static const uint32_t TAG_TAG = 0x3a474154;
static const uint32_t TAG_TT3 = 0x3a335454;
static const uint32_t TAG_TTI = 0x3a495454;
static const uint32_t TAG_VER = 0x3a524556;
static const uint32_t TAG_VGA = 0x3a414756;

class TaggedResource
: public ResourceData {
  private:
    std::map<const unsigned int, FileBuffer*> bufferMap;
  public:
    TaggedResource();
    virtual ~TaggedResource();
    void Clear();
    void Split(FileBuffer *buffer);
    bool Find(const unsigned label, FileBuffer* &buffer);
};

#endif

