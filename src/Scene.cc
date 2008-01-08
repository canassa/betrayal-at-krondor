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

#include "MediaToolkit.h"
#include "Scene.h"

Scene::Scene(Zone& z)
        : video(MediaToolkit::GetInstance()->GetVideo())
        , horizon(0)
        , terrainTexture(0)
        , objects()
        , spriteZBuffer()
        , terrainZBuffer()
{
    std::vector<Image *> images;
    images.push_back(z.GetHorizon(3));
    images.push_back(z.GetHorizon(0));
    images.push_back(z.GetHorizon(1));
    images.push_back(z.GetHorizon(2));
    images.push_back(z.GetHorizon(3));
    horizon = new Image(z.GetHorizon(0)->GetWidth() * 5, z.GetHorizon(0)->GetHeight(), images);
    images.clear();
    Image terrain1(z.GetTerrain()->GetWidth(), z.GetTerrain()->GetHeight() - 2, z.GetTerrain()->GetPixels());
    images.push_back(&terrain1);
    Image terrain2(z.GetTerrain()->GetWidth(), z.GetTerrain()->GetHeight() - 2, z.GetTerrain()->GetPixels() + z.GetTerrain()->GetWidth());
    images.push_back(&terrain2);
    Image terrain3(z.GetTerrain()->GetWidth(), z.GetTerrain()->GetHeight() - 2, z.GetTerrain()->GetPixels() + 2 * z.GetTerrain()->GetWidth());
    images.push_back(&terrain3);
    terrainTexture = new Image(z.GetTerrain()->GetWidth() * 3, z.GetTerrain()->GetHeight() - 2, images);
}

Scene::~Scene()
{
    for (std::multimap<const Vector2D, GenericObject *>::iterator it = objects.begin(); it != objects.end(); ++it)
    {
        delete (*it).second;
    }
    objects.clear();
    spriteZBuffer.clear();
    terrainZBuffer.clear();
    delete horizon;
    delete terrainTexture;
}

void
Scene::AddObject(const Vector2D &cell, GenericObject *obj)
{
    objects.insert(std::pair<const Vector2D, GenericObject *>(cell, obj));
}

void
Scene::FillZBuffer(Camera *cam)
{
    spriteZBuffer.clear();
    terrainZBuffer.clear();
    Vector2D cell = cam->GetPosition().GetCell();
    int heading = cam->GetHeading();
    for (std::multimap<const Vector2D, GenericObject *>::iterator it = objects.lower_bound(cell); it != objects.upper_bound(cell); ++it)
    {
        (*it).second->CalculateRelativePosition(cam->GetPosition().GetPos());
        Orientation orient(((*it).second->GetAngle() - heading) & ANGLE_MASK);
        int angle = orient.GetHeading();
        unsigned int distance = (*it).second->GetDistance();
        if ((distance < VIEW_DISTANCE) &&
            ((((int)(ANGLE_SIZE - ANGLE_OF_VIEW) <= angle) || (angle <= (int)ANGLE_OF_VIEW)) ||
             (((WEST < angle) || (angle < EAST)) && (abs((int)((float)distance * orient.GetSin())) < 128))))
        {
            SpritedObject* sprite = dynamic_cast<SpritedObject *>((*it).second);
            if (sprite != 0)
            {
                spriteZBuffer.insert(std::pair<int, SpritedObject *>(distance, sprite));
            }
            TerrainObject* terrain = dynamic_cast<TerrainObject *>((*it).second);
            if (terrain != 0)
            {
                terrainZBuffer.insert(std::pair<int, TerrainObject *>(distance, terrain));
            }
        }
    }
}

void
Scene::DrawHorizon(const int x, const int y, const int w, const int, const int heading)
{
    static const int HORIZON_TOP_SIZE = 34;
    video->FillRect(x, y, w, HORIZON_TOP_SIZE, horizon->GetPixel(0, 0));
    int xx = (heading << 2);
    video->FillRect(x, y + HORIZON_TOP_SIZE, w, horizon->GetHeight(), horizon->GetPixels(), xx - x, -y - HORIZON_TOP_SIZE, horizon->GetWidth());
}

void
Scene::DrawGround(const int x, const int y, const int w, const int h, Camera *cam)
{
    static const int TERRAIN_YOFFSET = 81;
    int offset = (((cam->GetHeading() * 16) + ((cam->GetPos().GetX() + cam->GetPos().GetY()) / 100)) % (terrainTexture->GetWidth() / 3));
    video->FillRect(x, y + h - TERRAIN_HEIGHT, w, TERRAIN_HEIGHT, terrainTexture->GetPixels(), offset - x, TERRAIN_YOFFSET - y - h + TERRAIN_HEIGHT, terrainTexture->GetWidth());
}

void
Scene::DrawZBuffer(const int x, const int y, const int w, const int h, const int heading)
{
    for (std::multimap<const unsigned int, TerrainObject *>::reverse_iterator it = terrainZBuffer.rbegin(); it != terrainZBuffer.rend(); it++)
    {
        (*it).second->DrawFirstPerson(x, y, w, h, heading);
    }
    for (std::multimap<const unsigned int, SpritedObject *>::reverse_iterator it = spriteZBuffer.rbegin(); it != spriteZBuffer.rend(); it++)
    {
        (*it).second->DrawFirstPerson(x, y, w, h, heading);
    }
}

void
Scene::DrawFirstPerson(const int x, const int y, const int w, const int h, Camera *cam)
{
    FillZBuffer(cam);
    DrawHorizon(x, y, w, h, cam->GetHeading());
    DrawGround(x, y, w, h, cam);
    DrawZBuffer(x, y, w, h, cam->GetHeading());
}

void
Scene::DrawTopDown()
{}
