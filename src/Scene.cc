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

static const int LOWER_ANGLE_OF_VIEW = 32;
static const int UPPER_ANGLE_OF_VIEW = 224;

static const unsigned int VIEW_DISTANCE = 8000 * 8000;

Scene::Scene(Zone& z)
: zone(z)
, objects()
, zBuffer()
{
}

Scene::~Scene()
{
  objects.clear();
  zBuffer.clear();
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
Scene::FillZBuffer(Camera *cam)
{
  for (std::list<GenericObject *>::iterator it = objects.begin(); it != objects.end(); it++) {
    (*it)->CalculateRelativePosition(cam->GetPosition().GetPos());
    int angle = (*it)->GetAngle(cam->GetHeading());
    unsigned int distance = (*it)->GetDistance();
    if (((angle <= LOWER_ANGLE_OF_VIEW) || (angle >= UPPER_ANGLE_OF_VIEW)) && (distance < VIEW_DISTANCE)) {
      zBuffer.insert(std::pair<int, GenericObject *>(distance, *it));
    }
  }
}

void
Scene::DrawHorizon(const int x, const int y, const int w, const int h, const int heading)
{
  static const int HORIZON_TOP_SIZE = 34;
  Image top(w, HORIZON_TOP_SIZE);
  int index = (heading >> 6) & 0x03;
  int imagewidth = zone.GetHorizon(index)->GetWidth();
  int imageheight = zone.GetHorizon(index)->GetHeight();
  int offset = imagewidth - ((heading & 0x3f) << 2);
  top.Fill(zone.GetHorizon(index)->GetPixel(0, 0));
  top.Draw(x, y);
  if (offset > 0) {
    zone.GetHorizon((index - 1) & 0x03)->Draw(x + offset - imagewidth, y + HORIZON_TOP_SIZE,
                                              imagewidth - offset, 0, offset, imageheight);
  }
  zone.GetHorizon(index)->Draw(x + offset, y + HORIZON_TOP_SIZE,
                               0, 0, imagewidth, imageheight);
  if (imagewidth + offset < w) {
    zone.GetHorizon((index + 1) & 0x03)->Draw(x + offset + imagewidth, y + HORIZON_TOP_SIZE,
                                              0, 0, w - offset - imagewidth, imageheight);
  }
}

void
Scene::DrawGround(const int x, const int y, const int w, const int h, Camera *cam)
{
  static const int TERRAIN_HEIGHT = 38;
  static const int TERRAIN_YOFFSET = 82;
  Image *terrain = zone.GetTerrain();
  int imagewidth = terrain->GetWidth();
  int offset = imagewidth - (((cam->GetHeading() * 16) + ((cam->GetPos().GetX() + cam->GetPos().GetY()) / 100)) % imagewidth);
  if (offset > 0) {
    terrain->Draw(x + offset - imagewidth, y + h - TERRAIN_HEIGHT - TERRAIN_YOFFSET + 1,
                  imagewidth - offset, TERRAIN_YOFFSET - 1, offset, TERRAIN_HEIGHT);
  }
  terrain->Draw(x + offset, y + h - TERRAIN_HEIGHT - TERRAIN_YOFFSET,
                0, TERRAIN_YOFFSET, imagewidth, TERRAIN_HEIGHT);
  if ((imagewidth + offset) < w) {
    terrain->Draw(x + offset + imagewidth, y + h - TERRAIN_HEIGHT - TERRAIN_YOFFSET - 1,
                  0, TERRAIN_YOFFSET + 1, w - offset - imagewidth, TERRAIN_HEIGHT);
  }
}

void
Scene::DrawZBuffer(const int x, const int y, const int w, const int h)
{
  if (x && y && w && h) {
  }
  for (std::map<int, GenericObject *>::reverse_iterator it = zBuffer.rbegin(); it != zBuffer.rend(); it++) {
  }
}

void
Scene::DrawFirstPerson(const int x, const int y, const int w, const int h, Camera *cam)
{
  FillZBuffer(cam);
  DrawHorizon(x, y, w, h, cam->GetHeading());
  DrawGround(x, y, w, h, cam);
  DrawZBuffer(x, y, w, h);
}

void
Scene::DrawTopDown()
{
}