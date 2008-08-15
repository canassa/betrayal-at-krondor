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
 * Copyright (C) 2007-2008 Guido de Jong <guidoj@users.sf.net>
 */

#include "MediaToolkit.h"
#include "Scene.h"

Scene::Scene(Image *horizon, Image *terrain)
        : video(MediaToolkit::GetInstance()->GetVideo())
        , horizonTexture(horizon)
        , terrainTexture(terrain)
        , sprites()
        , polygons()
        , spriteZBuffer()
        , polygonZBuffer()
{
}

Scene::~Scene()
{
    for (std::multimap<const Vector2D, SpriteObject *>::iterator it = sprites.begin(); it != sprites.end(); ++it)
    {
        delete it->second;
    }
    sprites.clear();
    for (std::multimap<const Vector2D, PolygonObject *>::iterator it = polygons.begin(); it != polygons.end(); ++it)
    {
        delete it->second;
    }
    polygons.clear();
    spriteZBuffer.clear();
    polygonZBuffer.clear();
    delete horizonTexture;
    delete terrainTexture;
}

void Scene::AddObject(const Vector2D &cell, SpriteObject *obj)
{
    sprites.insert(std::pair<const Vector2D, SpriteObject *>(cell, obj));
}

void Scene::AddObject(const Vector2D &cell, PolygonObject *obj)
{
    polygons.insert(std::pair<const Vector2D, PolygonObject *>(cell, obj));
}

void Scene::FillSpriteZBuffer(Camera *cam)
{
    spriteZBuffer.clear();
    Vector2D cell = cam->GetPosition().GetCell();
    int heading = cam->GetHeading();
    for (std::multimap<const Vector2D, SpriteObject *>::iterator it = sprites.lower_bound(cell); it != sprites.upper_bound(cell); ++it)
    {
        it->second->CalculateRelativePosition(cam->GetPosition().GetPos());
        unsigned int distance;
        if (it->second->IsInView(heading, distance))
        {
            spriteZBuffer.insert(std::pair<int, SpriteObject *>(distance, it->second));
        }
    }
}

void Scene::FillPolygonZBuffer(Camera *cam)
{
    polygonZBuffer.clear();
    Vector2D cell = cam->GetPosition().GetCell();
    int heading = cam->GetHeading();
    for (std::multimap<const Vector2D, PolygonObject *>::iterator it = polygons.lower_bound(cell - Vector2D(1,1));
         it != polygons.upper_bound(cell + Vector2D(1,1)); ++it)
    {
        it->second->CalculateRelativePosition(cam->GetPosition().GetPos());
        unsigned int distance;
        if (it->second->IsInView(heading, distance))
        {
            polygonZBuffer.insert(std::pair<int, PolygonObject *>(distance, it->second));
        }
    }
}

void Scene::DrawHorizon(const int x, const int y, const int w, const int, Camera *cam)
{
    static const int HORIZON_TOP_SIZE = 34;
    video->FillRect(x, y, w, HORIZON_TOP_SIZE, horizonTexture->GetPixel(0, 0));
    video->FillRect(x, y + HORIZON_TOP_SIZE, w, horizonTexture->GetHeight(), horizonTexture->GetPixels(),
                    (cam->GetHeading() << 2) - x, -y - HORIZON_TOP_SIZE, horizonTexture->GetWidth());
}

void Scene::DrawGround(const int x, const int y, const int w, const int h, Camera *cam)
{
    static const int TERRAIN_YOFFSET = 81;
    int offset = (((cam->GetHeading() * 16) + ((cam->GetPos().GetX() + cam->GetPos().GetY()) / 100)) % (terrainTexture->GetWidth() / 3));
    video->FillRect(x, y + h - TERRAIN_HEIGHT, w, TERRAIN_HEIGHT, terrainTexture->GetPixels(),
                    offset - x, TERRAIN_YOFFSET - y - h + TERRAIN_HEIGHT, terrainTexture->GetWidth());
}

void Scene::DrawZBuffer(const int x, const int y, const int w, const int h, Camera *cam)
{
    DrawGround(x, y, w, h, cam);
    for (std::multimap<const unsigned int, PolygonObject *>::reverse_iterator it = polygonZBuffer.rbegin(); it != polygonZBuffer.rend(); it++)
    {
        it->second->DrawFirstPerson(x, y, w, h, cam);
    }
    DrawHorizon(x, y, w, h, cam);
    for (std::multimap<const unsigned int, SpriteObject *>::reverse_iterator it = spriteZBuffer.rbegin(); it != spriteZBuffer.rend(); it++)
    {
        it->second->DrawFirstPerson(x, y, w, h, cam);
    }
}

void Scene::DrawFirstPerson(const int x, const int y, const int w, const int h, Camera *cam)
{
    FillSpriteZBuffer(cam);
    FillPolygonZBuffer(cam);
    DrawZBuffer(x, y, w, h, cam);
}

void Scene::DrawTopDown()
{
}
