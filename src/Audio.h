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

#ifndef AUDIO_H
#define AUDIO_H

#ifdef HAVE_CONFIG
#include "config.h"
#endif

#include "FileBuffer.h"

class Audio
{
public:
    Audio()
    {};
    virtual ~Audio()
    {};
    virtual int PlaySound ( FileBuffer *buffer, const int repeat = 0 ) = 0;
    virtual void StopSound ( const int channel = -1 ) = 0;
};

#endif
