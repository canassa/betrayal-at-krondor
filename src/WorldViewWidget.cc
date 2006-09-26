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

#include <iomanip>
#include <sstream>

#include "FileManager.h"
#include "WorldViewWidget.h"

WorldViewWidget::WorldViewWidget(const int x, const int y, const int w, const int h, Game *g)
: GameViewWidget(x, y, w, h, g)
{
}

WorldViewWidget::~WorldViewWidget()
{
}

void
WorldViewWidget::DrawHorizon()
{
  static const int HORIZON_TOP_SIZE = 20;
  int chapter = game->GetChapter()->Get();
  std::stringstream horizonStream;
  horizonStream << "Z" << std::setw(2) << std::setfill('0') << chapter << "H.BMX";
  ImageResource horizon;
  FileManager::GetInstance()->Load(&horizon, horizonStream.str());
  int heading = game->GetCamera()->GetHeading();
  int index = (heading >> 6) & 0x03;
  int imagewidth = horizon.GetImage(index)->GetWidth();
  int offset = (width >> 1) - ((heading & 0x3f) << 2);
  if (offset > 0) {
    horizon.GetImage((index - 1) & 0x03)->Draw(xpos + offset - imagewidth, ypos + HORIZON_TOP_SIZE, xpos, ypos + HORIZON_TOP_SIZE, width, height);
  }
  horizon.GetImage(index)->Draw(xpos + offset, ypos + HORIZON_TOP_SIZE, xpos, ypos + HORIZON_TOP_SIZE, width, height);
  if (imagewidth + offset < width) {
    horizon.GetImage((index + 1) & 0x03)->Draw(xpos + offset + imagewidth, ypos + HORIZON_TOP_SIZE, xpos, ypos + HORIZON_TOP_SIZE, width, height);
  }
}

void
WorldViewWidget::Redraw()
{
  DrawHorizon();
}
