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

#ifndef MOVIE_PLAYER_H
#define MOVIE_PLAYER_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "EventHandler.h"
#include "MediaToolkit.h"
#include "MovieResource.h"
#include "ImageResource.h"
#include "PaletteResource.h"
#include "ScreenResource.h"

static const unsigned int MAX_IMAGE_SLOTS   = 4;
static const unsigned int MAX_PALETTE_SLOTS = 4;

class MoviePlayer: public EventHandler {
  private:
    MediaToolkit *media;
    std::vector<MovieTag *> *tagVec;
    ScreenResource* screenSlot;
    ImageResource* imageSlot[MAX_IMAGE_SLOTS];
    PaletteResource* paletteSlot[MAX_PALETTE_SLOTS];
    Image *savedImage;
    bool savedImageDrawn;
    unsigned int currFrame;
    unsigned int currImage;
    unsigned int currPalette;
    unsigned int currTag;
    unsigned int currDelay;
    bool paletteActivated;
    bool looped;
  public:
    MoviePlayer(MediaToolkit *mtk);
    ~MoviePlayer();
    void Play(std::vector<MovieTag *> *movie, const bool repeat);
    bool HandleKeyboardEvent(int key, bool down);
    bool HandleMouseButtonEvent(int button, int x, int y, bool down);
    bool HandleMouseMotionEvent(int x, int y);
    bool HandleUpdateEvent();
};

#endif
