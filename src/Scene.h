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
 * Copyright (C) 2007 Guido de Jong <guidoj@users.sf.net>
 */

#ifndef SCENE_H
#define SCENE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <list>
#include <map>

#include "Camera.h"
#include "GenericObject.h"
#include "Zone.h"

class Scene {
  private:
    Zone& zone;
    std::multimap<const Vector2D, GenericObject *> objects;
    std::multimap<const unsigned int, GenericObject *> zBuffer;
    void FillZBuffer(Camera *cam);
    void DrawHorizon(const int x, const int y, const int w, const int h, const int heading);
    void DrawGround(const int x, const int y, const int w, const int h, Camera *cam);
    void DrawZBuffer(const int x, const int y, const int w, const int h, const int heading);
  public:
    Scene(Zone& z);
    ~Scene();
    void AddObject(const Vector2D &cell, GenericObject *obj);
    void DrawFirstPerson(const int x, const int y, const int w, const int h, Camera *cam);
    void DrawTopDown();
};

#endif
