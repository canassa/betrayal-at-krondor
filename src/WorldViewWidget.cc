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
#include "ImageResource.h"
#include "MediaToolkit.h"
#include "ScreenResource.h"
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
  std::stringstream stream;
  stream << "Z" << std::setw(2) << std::setfill('0') << game->GetChapter()->Get() << "H.BMX";
  ImageResource horizon;
  FileManager::GetInstance()->Load(&horizon, stream.str());
  Image top(width, HORIZON_TOP_SIZE);
  int heading = game->GetCamera()->GetHeading();
  int index = (heading >> 6) & 0x03;
  int imagewidth = horizon.GetImage(index)->GetWidth();
  int offset = imagewidth - xpos - ((heading & 0x3f) << 2);
  top.Fill(horizon.GetImage(index)->GetPixel(0, 0));
  top.Draw(xpos, ypos);
  if (offset > 0) {
    horizon.GetImage((index - 1) & 0x03)->Draw(xpos + offset - imagewidth, ypos + HORIZON_TOP_SIZE, xpos, ypos + HORIZON_TOP_SIZE, width, height);
  }
  horizon.GetImage(index)->Draw(xpos + offset, ypos + HORIZON_TOP_SIZE, xpos, ypos + HORIZON_TOP_SIZE, width, height);
  if (imagewidth + offset < width) {
    horizon.GetImage((index + 1) & 0x03)->Draw(xpos + offset + imagewidth, ypos + HORIZON_TOP_SIZE, xpos, ypos + HORIZON_TOP_SIZE, width, height);
  }
}

void
WorldViewWidget::DrawTerrain()
{
  static const int TERRAIN_HEIGHT = 38;
  static const int TERRAIN_YOFFSET = -82;
  static const int TERRAIN_IMAGE_WIDTH = 172;
  static const int TERRAIN_IMAGE_HEIGHT = 130;
  std::stringstream stream;
  stream << "Z" << std::setw(2) << std::setfill('0') << game->GetChapter()->Get() << "L.SCX";
  ScreenResource terrain;
  FileManager::GetInstance()->Load(&terrain, stream.str());
  Image *terrainImage = new Image(TERRAIN_IMAGE_WIDTH, TERRAIN_IMAGE_HEIGHT, terrain.GetImage()->GetPixels());
  int offset = TERRAIN_IMAGE_WIDTH - xpos - ((game->GetCamera()->GetHeading() * 16) % TERRAIN_IMAGE_WIDTH);
  if (offset > 0) {
    terrainImage->Draw(xpos + offset - TERRAIN_IMAGE_WIDTH, ypos + 1 + height - TERRAIN_HEIGHT + TERRAIN_YOFFSET, xpos, ypos + height - TERRAIN_HEIGHT, width, TERRAIN_HEIGHT);
  }
  terrainImage->Draw(xpos + offset, ypos + height - TERRAIN_HEIGHT + TERRAIN_YOFFSET, xpos, ypos + height - TERRAIN_HEIGHT, width, TERRAIN_HEIGHT);
  if ((TERRAIN_IMAGE_WIDTH + offset) < width) {
    terrainImage->Draw(xpos + offset + TERRAIN_IMAGE_WIDTH, ypos - 1 + height - TERRAIN_HEIGHT + TERRAIN_YOFFSET, xpos, ypos + height - TERRAIN_HEIGHT, width, TERRAIN_HEIGHT);
  }
}

void
WorldViewWidget::Redraw()
{
  MediaToolkit::GetInstance()->GetVideo()->Clear(xpos, ypos, width, height);
  DrawHorizon();
  DrawTerrain();
}
