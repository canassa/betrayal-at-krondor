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

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "FileManager.h"
#include "MousePointer.h"

MousePointer::MousePointer(const std::string &resname)
: visible(false)
, xPos(0)
, yPos(0)
, pointerType(MP_SWORD)
, pointerImages()
{
  FileManager::GetInstance()->Load(&pointerImages, resname);
}

MousePointer::~MousePointer()
{
}

void
MousePointer::SetPointerType(MousePointerType mpt)
{
  pointerType = mpt;
}

void
MousePointer::SetPosition(const int x, const int y)
{
  xPos = x;
  yPos = y;
}

void
MousePointer::SetVisible(const bool vis)
{
  visible = vis;
}

void
MousePointer::Draw()
{
  if (visible) {
    pointerImages.GetImage((int)pointerType)->Draw(xPos, yPos, 0);
  }
}

