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

#ifndef MOUSE_POINTER_MANAGER_H
#define MOUSE_POINTER_MANAGER_H

#include <string>
#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "EventListener.h"
#include "MediaToolkit.h"
#include "MousePointer.h"

static const unsigned int NORMAL_POINTER = 0;
static const unsigned int SPECIAL_POINTER = 1;

class MousePointerManager: public MouseMotionEventListener {
  private:
    unsigned int currentPointer;
    std::vector<MousePointer *> pointerVec;
    static MousePointerManager *instance;
  protected:
    MousePointerManager();
  public:
    ~MousePointerManager();
    static MousePointerManager* GetInstance();
    void Register(MediaToolkit *media);
    MousePointer* GetCurrentPointer();
    void SetCurrentPointer(unsigned int n);
    void AddPointer(const std::string& resname);
    void MouseMoved(const MouseMotionEvent &mme);
};

#endif

