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

#ifndef TEXT_WIDGET_H
#define TEXT_WIDGET_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <string>

#include "FontResource.h"
#include "Widget.h"

typedef enum {
  HA_LEFT,
  HA_CENTER,
  HA_RIGHT
} HorizontalAlignment;

typedef enum  {
  VA_TOP,
  VA_CENTER,
  VA_BOTTOM
} VerticalAlignment;

class TextWidget
: public Widget {
  private:
    FontResource& font;
    std::string text;
    int textWidth;
    int textHeight;
    int color;
    int shadow;
    HorizontalAlignment horAlign;
    VerticalAlignment vertAlign;
  public:
    TextWidget(const int x, const int y, const int w, const int h, FontResource& f);
    virtual ~TextWidget();
    void Draw();
    void SetColor(const int c);
    void SetText(const std::string& s);
    void SetShadow(const int s);
    void SetAlignment(const HorizontalAlignment ha, const VerticalAlignment va);
};

#endif
