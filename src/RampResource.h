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
 * Copyright (C) 2009 Guido de Jong <guidoj@users.sf.net>
 */

#ifndef RAMP_RESOURCE_H
#define RAMP_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "ResourceData.h"

class RampResource
            : public ResourceData
{
private:
    std::vector < std::vector <unsigned char> > ramp;
public:
    RampResource();
    virtual ~RampResource();
    unsigned int GetSize() const;
    std::vector<unsigned char>& GetRamp ( unsigned int rmp );
    unsigned char GetColor ( unsigned int rmp, unsigned int n ) const;
    void Clear();
    void Load ( FileBuffer *buffer );
    unsigned int Save ( FileBuffer *buffer );
};

#endif