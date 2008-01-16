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

#ifndef PALETTE_H
#define PALETTE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "MediaToolkit.h"

class Palette
{
private:
    unsigned int size;
    Color *colors;
    bool delayed;
    MediaToolkit *media;
public:
    Palette ( const unsigned int n );
    ~Palette();
    unsigned int GetSize() const;
    Color& GetColor ( const unsigned int i ) const;
    void SetColor ( const unsigned int i, const Color &c );
    void Fill();
    void Activate ( const unsigned int first, const unsigned int n );
    void Retrieve ( const unsigned int first, const unsigned int n );
    void FadeFrom ( Color* from, const unsigned int first, const unsigned int n, const unsigned int steps, const unsigned int delay );
    void FadeTo ( Color* from, const unsigned int first, const unsigned int n, const unsigned int steps, const unsigned int delay );
    void FadeIn ( const unsigned int first, const unsigned int n, const unsigned int steps, const unsigned int delay );
    void FadeOut ( const unsigned int first, const unsigned int n, const unsigned int steps, const unsigned int delay );
    void TimerExpired ( const TimerEvent &te );
};

#endif

