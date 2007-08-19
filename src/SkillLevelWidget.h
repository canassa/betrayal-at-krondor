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

#ifndef SKILL_LEVEL_WIDGET_H
#define SKILL_LEVEL_WIDGET_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <string>

#include "Image.h"
#include "TextWidget.h"
#include "Widget.h"

typedef enum _Side {
    LEFT_SIDE, RIGHT_SIDE
} Side;

class SkillLevelWidget
            : public Widget
{
private:
    Side side;
    Image *sword;
    Image *blood;
    TextWidget *skill;
    TextWidget *level;
    int value;
public:
    SkillLevelWidget ( const Rectangle &r, const Side s, Image *sw, Image *bl, Font *f );
    virtual ~SkillLevelWidget();
    void SetLevel ( const std::string& s, const int v );
    void Draw();
};

#endif
