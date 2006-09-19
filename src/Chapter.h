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

#ifndef CHAPTER_H
#define CHAPTER_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "EventListener.h"

class Chapter
: public KeyboardEventListener
, public MouseButtonEventListener
, public TimerEventListener
, public FadeCompleteEventListener
{
  private:
    int number;
  public:
    Chapter(const int n);
    ~Chapter();
    void PlayIntro();
    void PlayScene(const int scene);
    void ReadBook(const int scene);
    void ShowMap();
    void KeyPressed(const KeyboardEvent &kbe);
    void KeyReleased(const KeyboardEvent &kbe);
    void MouseButtonPressed(const MouseButtonEvent &mbe);
    void MouseButtonReleased(const MouseButtonEvent &mbe);
    void TimerExpired(const TimerEvent &te);
    void FadeComplete();
};

#endif
