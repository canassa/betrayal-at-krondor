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

#ifndef PORTRAIT_WIDGET_H
#define PORTRAIT_WIDGET_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Image.h"
#include "PlayerCharacter.h"
#include "Widget.h"

class PortraitWidget
: public Widget {
  private:
    PlayerCharacter *playerCharacter;
    Image *horizontalBorder;
    Image *verticalBorder;
  public:
    PortraitWidget(const int x, const int y, const int w, const int h, PlayerCharacter *pc);
    virtual ~PortraitWidget();
    void SetBorders(Image *hb, Image *vb);
    void Draw();
};

#endif
