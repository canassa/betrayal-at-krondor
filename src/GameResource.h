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
 * Copyright (C) 2005-2009 Guido de Jong <guidoj@users.sf.net>
 */

#ifndef GAME_RESOURCE_H
#define GAME_RESOURCE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <string>
#include <vector>

#include "FileBuffer.h"
#include "Game.h"
#include "GameData.h"

class GameResource
            : public GameData
{
private:
    Game *game;
    unsigned int zone;
    unsigned int xloc;
    unsigned int yloc;
public:
    GameResource();
    virtual ~GameResource();
    Game * GetGame();
    void SetGame ( Game *g );
    unsigned int GetZone() const;
    void SetZone ( const unsigned int z );
    unsigned int GetXLoc() const;
    void SetXLoc ( const unsigned int x );
    unsigned int GetYLoc() const;
    void SetYLoc ( const unsigned int y );
    void Load ( FileBuffer *buffer );
    unsigned int Save ( FileBuffer *buffer );
};

#endif
