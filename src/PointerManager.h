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
 * Copyright (C) 2005-2008 Guido de Jong <guidoj@users.sf.net>
 */

#ifndef POINTER_MANAGER_H
#define POINTER_MANAGER_H

#include <string>
#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "EventListener.h"
#include "InventoryItemWidget.h"
#include "Pointer.h"

static const unsigned int NORMAL_POINTER = 0;
static const unsigned int SPECIAL_POINTER = 1;

class PointerManager
            : public PointerButtonEventListener
            , public PointerMotionEventListener
{
private:
    unsigned int currentPointer;
    bool pressed;
    bool dragged;
    InventoryItemWidget *itemWidget;
    std::vector<Pointer *> pointerVec;
    std::list<DragEventListener *> dragListeners;
    static PointerManager *instance;
protected:
    PointerManager();
public:
    ~PointerManager();
    static PointerManager* GetInstance();
    static void CleanUp();
    Pointer* GetCurrentPointer();
    void SetCurrentPointer ( unsigned int n );
    InventoryItemWidget* GetDraggedWidget ( void );
    void SetDraggedWidget ( InventoryItemWidget *widget, const int x, const int y );
    void AddPointer ( const std::string& resname );
    void PointerButtonPressed ( const PointerButtonEvent &pbe );
    void PointerButtonReleased ( const PointerButtonEvent &pbe );
    void PointerMoved ( const PointerMotionEvent &pme );
    void AddDragListener ( DragEventListener *del );
    void RemoveDragListener ( DragEventListener *del );
};

#endif
