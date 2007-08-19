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

#ifndef NULL_AUDIO_H
#define NULL_AUDIO_H

#ifdef HAVE_CONFIG
#include "config.h"
#endif

#include "Audio.h"

class Null_Audio
            : public Audio
{
public:
    Null_Audio();
    virtual ~Null_Audio();
    int PlaySound ( FileBuffer *buffer, const int repeat = 0 );
    void StopSound ( const int channel = -1 );
};

#endif
