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

#ifndef MEDIA_TOOLKIT_H
#define MEDIA_TOOLKIT_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <list>

#include "Audio.h"
#include "Clock.h"
#include "EventListener.h"
#include "Video.h"

class MediaToolkit
{
private:
    static MediaToolkit* instance;
protected:
    Audio *audio;
    Clock *clock;
    Video *video;
    bool eventLoopRunning;
    std::list<KeyboardEventListener *> keyboardListeners;
    std::list<PointerButtonEventListener *> pointerButtonListeners;
    std::list<PointerMotionEventListener *> pointerMotionListeners;
    std::list<TimerEventListener *> timerListeners;
    std::list<LoopEventListener *> loopListeners;
public:
    MediaToolkit();
    virtual ~MediaToolkit();
    static MediaToolkit* GetInstance();
    static void CleanUp();
    Audio* GetAudio() const;
    Clock* GetClock() const;
    Video* GetVideo() const;
    void AddKeyboardListener ( KeyboardEventListener *kel );
    void RemoveKeyboardListener ( KeyboardEventListener *kel );
    void AddPointerButtonListener ( PointerButtonEventListener *pbel );
    void RemovePointerButtonListener ( PointerButtonEventListener *pbel );
    void AddPointerMotionListener ( PointerMotionEventListener *pmel );
    void RemovePointerMotionListener ( PointerMotionEventListener *pmel );
    void AddTimerListener ( TimerEventListener *tel );
    void RemoveTimerListener ( TimerEventListener *tel );
    void AddUpdateListener ( LoopEventListener *lel );
    void RemoveUpdateListener ( LoopEventListener *lel );
    void TerminateEventLoop();
    virtual void PollEvents() = 0;
    virtual void PollEventLoop() = 0;
    virtual void WaitEvents() = 0;
    virtual void WaitEventLoop() = 0;
    virtual void ClearEvents() = 0;
    virtual void GetPointerPosition ( int *x, int *y ) = 0;
    virtual void SetPointerPosition ( int x, int y ) = 0;
};

#endif
