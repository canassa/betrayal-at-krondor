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

#ifndef CHAPTER_H
#define CHAPTER_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "EventListener.h"
#include "Zone.h"

class Chapter
            : public KeyboardEventListener
            , public PointerButtonEventListener
            , public TimerEventListener
{
private:
    int number;
    bool delayed;
    Zone zone;
    void PlayIntro();
    void PlayScene ( const int scene );
    void ReadBook ( const int scene );
    void ShowMap();
public:
    Chapter ( const int n );
    virtual ~Chapter();
    int Get() const;
    Zone& GetZone();
    void Next();
    void Start ( const bool maponly = false );
    void KeyPressed ( const KeyboardEvent &kbe );
    void KeyReleased ( const KeyboardEvent &kbe );
    void PointerButtonPressed ( const PointerButtonEvent &pbe );
    void PointerButtonReleased ( const PointerButtonEvent &pbe );
    void TimerExpired ( const TimerEvent &te );
};

#endif
