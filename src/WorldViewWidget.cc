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

#include "Image.h"
#include "MediaToolkit.h"
#include "WorldViewWidget.h"

WorldViewWidget::WorldViewWidget(const int x, const int y, const int w, const int h, Game *g)
: GameViewWidget(x, y, w, h, g)
{
  game->GetCamera()->Attach(this);
  Update();
}

WorldViewWidget::~WorldViewWidget()
{
  game->GetCamera()->Detach(this);
}

void
WorldViewWidget::DrawHorizon()
{
  static const int HORIZON_TOP_SIZE = 34;
  Image top(width, HORIZON_TOP_SIZE);
  int heading = game->GetCamera()->GetHeading();
  int index = (heading >> 6) & 0x03;
  int imagewidth = game->GetChapter()->GetZone().GetHorizon(index)->GetWidth();
  int imageheight = game->GetChapter()->GetZone().GetHorizon(index)->GetHeight();
  int offset = imagewidth - ((heading & 0x3f) << 2);
  top.Fill(game->GetChapter()->GetZone().GetHorizon(index)->GetPixel(0, 0));
  top.Draw(xpos, ypos);
  if (offset > 0) {
    game->GetChapter()->GetZone().GetHorizon((index - 1) & 0x03)->Draw(xpos + offset - imagewidth, ypos + HORIZON_TOP_SIZE,
                                                                       imagewidth - offset, 0, offset, imageheight);
  }
  game->GetChapter()->GetZone().GetHorizon(index)->Draw(xpos + offset, ypos + HORIZON_TOP_SIZE,
                                                        0, 0, imagewidth, imageheight);
  if (imagewidth + offset < width) {
    game->GetChapter()->GetZone().GetHorizon((index + 1) & 0x03)->Draw(xpos + offset + imagewidth, ypos + HORIZON_TOP_SIZE,
                                                                       0, 0, width - offset - imagewidth, imageheight);
  }
}

void
WorldViewWidget::DrawTerrain()
{
  static const int TERRAIN_HEIGHT = 38;
  static const int TERRAIN_YOFFSET = 82;
  Image *terrain = game->GetChapter()->GetZone().GetTerrain();
  int imagewidth = terrain->GetWidth();
  int offset = imagewidth -
               (((game->GetCamera()->GetHeading() * 16) + ((game->GetCamera()->GetXPos() + game->GetCamera()->GetYPos()) / 100)) % imagewidth);
  if (offset > 0) {
    terrain->Draw(xpos + offset - imagewidth, ypos + height - TERRAIN_HEIGHT - TERRAIN_YOFFSET + 1,
                  imagewidth - offset, TERRAIN_YOFFSET - 1, offset, TERRAIN_HEIGHT);
  }
  terrain->Draw(xpos + offset, ypos + height - TERRAIN_HEIGHT - TERRAIN_YOFFSET,
                0, TERRAIN_YOFFSET, imagewidth, TERRAIN_HEIGHT);
  if ((imagewidth + offset) < width) {
    terrain->Draw(xpos + offset + imagewidth, ypos + height - TERRAIN_HEIGHT - TERRAIN_YOFFSET - 1,
                  0, TERRAIN_YOFFSET + 1, width - offset - imagewidth, TERRAIN_HEIGHT);
  }
}

void
WorldViewWidget::Redraw()
{
  MediaToolkit::GetInstance()->GetVideo()->Clear(xpos, ypos, width, height);
  DrawHorizon();
  DrawTerrain();
}
