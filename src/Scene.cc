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
 * Copyright (C) 2006 Guido de Jong <guidoj@users.sf.net>
 */

#include "Scene.h"

Scene::Scene(Zone& z)
: zone(z)
, objects()
{
}

Scene::~Scene()
{
  objects.clear();
}

void
Scene::AddObject(GenericObject *obj)
{
  objects.push_back(obj);
}

void
Scene::RemoveObject(GenericObject *obj)
{
  objects.remove(obj);
}

void
Scene::DrawHorizon(const int xpos, const int ypos, const int width, const int height, const int heading)
{
  static const int HORIZON_TOP_SIZE = 34;
  Image top(width, HORIZON_TOP_SIZE);
  int index = (heading >> 6) & 0x03;
  int imagewidth = zone.GetHorizon(index)->GetWidth();
  int imageheight = zone.GetHorizon(index)->GetHeight();
  int offset = imagewidth - ((heading & 0x3f) << 2);
  top.Fill(zone.GetHorizon(index)->GetPixel(0, 0));
  top.Draw(xpos, ypos);
  if (offset > 0) {
    zone.GetHorizon((index - 1) & 0x03)->Draw(xpos + offset - imagewidth, ypos + HORIZON_TOP_SIZE,
                                               imagewidth - offset, 0, offset, imageheight);
  }
  zone.GetHorizon(index)->Draw(xpos + offset, ypos + HORIZON_TOP_SIZE,
                                0, 0, imagewidth, imageheight);
  if (imagewidth + offset < width) {
    zone.GetHorizon((index + 1) & 0x03)->Draw(xpos + offset + imagewidth, ypos + HORIZON_TOP_SIZE,
                                               0, 0, width - offset - imagewidth, imageheight);
  }
}

void
Scene::DrawGround(const int xpos, const int ypos, const int width, const int height, Camera *cam)
{
  static const int TERRAIN_HEIGHT = 38;
  static const int TERRAIN_YOFFSET = 82;
  Image *terrain = zone.GetTerrain();
  int imagewidth = terrain->GetWidth();
  int offset = imagewidth - (((cam->GetHeading() * 16) + ((cam->GetXPos() + cam->GetYPos()) / 100)) % imagewidth);
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
Scene::DrawFirstPerson(const int xpos, const int ypos, const int width, const int height, Camera *cam)
{
  DrawHorizon(xpos, ypos, width, height, cam->GetHeading());
  DrawGround(xpos, ypos, width, height, cam);
}

void
Scene::DrawTopDown()
{
}
