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

#ifndef MOUSE_POINTER_H
#define MOUSE_POINTER_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "ImageResource.h"
#include "Subject.h"
#include "Video.h"

typedef enum _MousePointerType {
  MP_SWORD = 0,
  MP_HAND = 1,
  MP_HOURGLASS = 2,
  MP_LOOKING_GLASS = 3,
  MP_EXIT = 4,
  MP_INN = 5,
  MP_TAVERN = 6,
  MP_SHOP = 7,
  MP_PALACE = 8,
  MP_TEMPLE = 9,
  MP_HOUSE = 10,
  MP_TELEPORT = 11,
  MP_PETITION = 12,
  MP_BARD = 13,
  MP_TALK = 14,
  MP_BUY_SELL = 15,
  MP_ENTER = 16,
  MP_REPAIR = 17,
  MP_BUY = 18,
  MP_HAND2 = 19,
  MP_GAB = 20,
  MP_CHAT = 21,
  MP_SEWER = 22,
  MP_BAR = 23,
  MP_BARMAID = 24,
  MP_BARKEEP = 25,
  MP_INNKEEPER = 26
} MousePointerType;

class MousePointer
: public Subject {
  private:
    bool visible;
    int xPos;
    int yPos;
    MousePointerType pointerType;
    ImageResource pointerImages;
  public:
    MousePointer(const std::string &resname);
    virtual ~MousePointer();
    int GetXPos() const;
    int GetYPos() const;
    void SetPointerType(MousePointerType mpt);
    void SetPosition(const int x, const int y);
    void SetVisible(const bool vis);
    void Draw();
};

#endif

