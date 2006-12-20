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

#ifndef ZONE_H
#define ZONE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <vector>

#include "ImageResource.h"
#include "TableResource.h"

class Zone {
  private:
    ImageResource horizon;
    Image *terrain;
    std::vector<Image *> sprites;
    TableResource table;
  public:
    Zone();
    ~Zone();
    void Load(const unsigned int n);
    Image* GetHorizon(const unsigned int n);
    Image* GetSprite(const unsigned int n);
    Image* GetTerrain() const;
    TableResource& GetTable();
};

#endif
