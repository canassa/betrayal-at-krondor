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

#include "LabelWidget.h"

LabelWidget::LabelWidget(const int x, const int y, const int w, const int h, FontResource& f)
: Widget(x, y, w, h)
, font(f)
, text("")
, textWidth(0)
, textHeight(0)
, color(0)
, shadow(NO_SHADOW)
, horAlign(HA_CENTER)
, vertAlign(VA_CENTER)
{
}

LabelWidget::~LabelWidget()
{
}

void
LabelWidget::SetText(const std::string &s)
{
  text = s;
  textWidth = 0;
  for (unsigned int i = 0; i < text.length(); i++) {
    textWidth += font.GetWidth(text[i] - font.GetFirst());
  }
  textHeight = font.GetHeight();
}

void
LabelWidget::SetColor(const int c)
{
  color = c;
}

void
LabelWidget::SetShadow(const int s)
{
  shadow = s;
}

void
LabelWidget::SetAlignment(const HorizontalAlignment ha, const VerticalAlignment va)
{
  horAlign = ha;
  vertAlign = va;
}

void
LabelWidget::Draw()
{
  unsigned int i;
  unsigned int w;
  int xoff = 0;
  int yoff = 0;
  switch (horAlign) {
    case HA_LEFT:
      xoff = 0;
      break;
    case HA_CENTER:
      xoff = (width - textWidth) / 2;
      break;
    case HA_RIGHT:
      xoff = width - textWidth;
      break;
  }
  switch (vertAlign) {
    case VA_TOP:
      yoff = 0;
      break;
    case VA_CENTER:
      yoff = (height - textHeight) / 2;
      break;
    case VA_BOTTOM:
      yoff = height - textHeight;
      break;
  }
  if (shadow > NO_SHADOW) {
    i = 0;
    w = 0;
    while ((i < text.length()) && (w + font.GetWidth(text[i] - font.GetFirst()) < (unsigned)width)) {
      font.DrawChar(xpos + xoff + w, ypos + yoff + 1, text[i], shadow, false);
      w += font.GetWidth((unsigned int)text[i] - font.GetFirst());
      i++;
    }
  }
  i = 0;
  w = 0;
  while ((i < text.length()) && (w + font.GetWidth(text[i] - font.GetFirst()) < (unsigned)width)) {
    font.DrawChar(xpos + xoff + w, ypos + yoff, text[i], color, false);
    w += font.GetWidth((unsigned int)text[i] - font.GetFirst());
    i++;
  }
}
