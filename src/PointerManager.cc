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

#include "ImageResource.h"
#include "MediaToolkit.h"
#include "PointerManager.h"

PointerManager* PointerManager::instance = 0;

PointerManager::PointerManager()
        : currentPointer(0)
        , pointerVec()
{
    MediaToolkit::GetInstance()->AddMouseButtonListener(this);
    MediaToolkit::GetInstance()->AddMouseMotionListener(this);
}

PointerManager::~PointerManager()
{
    MediaToolkit::GetInstance()->RemoveMouseButtonListener(this);
    MediaToolkit::GetInstance()->RemoveMouseMotionListener(this);
    for (unsigned int i = 0; i < pointerVec.size(); i++)
    {
        delete pointerVec[i];
    }
    pointerVec.clear();
}

PointerManager*
PointerManager::GetInstance()
{
    if (!instance)
    {
        instance = new PointerManager();
    }
    return instance;
}

void
PointerManager::CleanUp()
{
    if (instance)
    {
        delete instance;
        instance = 0;
    }
}

Pointer*
PointerManager::GetCurrentPointer()
{
    return pointerVec[currentPointer];
}

void
PointerManager::SetCurrentPointer(const unsigned int n)
{
    if (n < pointerVec.size())
    {
        currentPointer = n;
    }
    else
    {
        currentPointer = 0;
    }
}

void
PointerManager::AddPointer(const std::string& resname)
{
    Pointer *mp = new Pointer(resname);
    pointerVec.push_back(mp);
}

void
PointerManager::MouseButtonPressed(const MouseButtonEvent &mbe)
{
    pointerVec[currentPointer]->SetPosition(mbe.GetXPos(), mbe.GetYPos());
}

void
PointerManager::MouseButtonReleased(const MouseButtonEvent &mbe)
{
    pointerVec[currentPointer]->SetPosition(mbe.GetXPos(), mbe.GetYPos());
}

void
PointerManager::MouseMoved(const MouseMotionEvent &mme)
{
    pointerVec[currentPointer]->SetPosition(mme.GetXPos(), mme.GetYPos());
}
