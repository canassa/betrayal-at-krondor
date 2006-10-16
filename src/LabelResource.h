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

#ifndef LABEL_RESOURCE_H
#define LABEL_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "ResourceData.h"

static const int LBL_STANDARD = 0;
static const int LBL_TITLE    = 3;

typedef struct _LabelData {
  int xpos;
  int ypos;
  int type;
  int color;
  int shadow;
  std::string label;
} LabelData;

class LabelResource
: public ResourceData {
  private:
    std::vector<LabelData> data;
  public:
    LabelResource();
    virtual ~LabelResource();
    unsigned int GetSize() const;
    LabelData GetLabelData(const unsigned int n) const;
    void Clear();
    void Load(FileBuffer *buffer);
};

#endif

