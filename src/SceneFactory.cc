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

#include "MeshedObject.h"
#include "SceneFactory.h"
#include "SpritedObject.h"
#include "TerrainObject.h"

SceneFactory::SceneFactory(Zone &z)
    : zone(z)
{
}

SceneFactory::~SceneFactory()
{
}

void SceneFactory::AddFixedObjects(Scene* scene)
{
    TableResource *table = zone.GetTable();
    if (scene && table)
    {
        for (unsigned int i = 0; i < table->GetMapSize(); i++)
        {
            DatInfo *dat = table->GetDatItem(i);
            switch (dat->objectType)
            {
                case OT_FIELD:
/*                    {
                        TerrainObject *terrObj = new TerrainObject();
                        for (unsigned j = 0; j < dat->vertices.size(); j++)
                        {
                            terrObj->AddVertex(Vertex(*(dat->vertices[j])));
                        }
                        scene->AddObject(Vector2D(x, y), terrObj);
                    }
                    break;*/
                default:
                    break;
            }
        }
    }
}

void SceneFactory::AddTiledObjects(Scene* scene, unsigned int x, unsigned int y, Image *terrainTexture)
{
    TableResource *table = zone.GetTable();
    TileWorldResource *tile = zone.GetTile(x, y);
    if (scene && table && tile)
    {
        for (unsigned int i = 0; i < tile->GetSize(); i++)
        {
            TileWorldItem item = tile->GetItem(i);
            DatInfo *dat = table->GetDatItem(item.type);
            switch (dat->objectType)
            {
                case OT_TERRAIN:
                    {
                        TerrainObject *terrObj = new TerrainObject(terrainTexture);
                        for (unsigned j = 0; j < dat->vertices.size(); j++)
                        {
                            terrObj->AddVertex(Vertex(*(dat->vertices[j])));
                        }
                        scene->AddObject(Vector2D(x, y), terrObj);
                    }
                    break;
                case OT_TREE:
                case OT_TOMBSTONE:
                case OT_SIGN:
                case OT_DEADBODY2:
                case OT_DIRTPILE:
                case OT_FIRE:
                case OT_FERN:
                case OT_ROCKPILE:
                case OT_BUSH1:
                case OT_BUSH2:
                case OT_BUSH3:
                case OT_SLAB:
                case OT_STUMP:
                case OT_WELL:
                case OT_ENGINE:
                case OT_SCARECROW:
                case OT_TRAP:
                case OT_COLUMN:
                case OT_BAG:
                case OT_LADDER:
                    scene->AddObject(Vector2D(x, y), new SpritedObject(Vector2D(item.xloc, item.yloc), zone.GetSprite(dat->sprite)));
                    break;
                default:
                    break;
            }
        }
    }
}

Scene * SceneFactory::CreateScene()
{
    std::vector<Image *> horizonImages;
    horizonImages.push_back(zone.GetHorizon(3));
    horizonImages.push_back(zone.GetHorizon(0));
    horizonImages.push_back(zone.GetHorizon(1));
    horizonImages.push_back(zone.GetHorizon(2));
    horizonImages.push_back(zone.GetHorizon(3));
    Image *horizonTexture = new Image(zone.GetHorizon(0)->GetWidth() * 5, zone.GetHorizon(0)->GetHeight(), horizonImages);
    std::vector<Image *> terrainImages;
    Image terrain1(zone.GetTerrain()->GetWidth(), zone.GetTerrain()->GetHeight() - 2, zone.GetTerrain()->GetPixels());
    terrainImages.push_back(&terrain1);
    Image terrain2(zone.GetTerrain()->GetWidth(), zone.GetTerrain()->GetHeight() - 2, zone.GetTerrain()->GetPixels() + zone.GetTerrain()->GetWidth());
    terrainImages.push_back(&terrain2);
    Image terrain3(zone.GetTerrain()->GetWidth(), zone.GetTerrain()->GetHeight() - 2, zone.GetTerrain()->GetPixels() + 2 * zone.GetTerrain()->GetWidth());
    terrainImages.push_back(&terrain3);
    Image *terrainTexture = new Image(zone.GetTerrain()->GetWidth() * 3, zone.GetTerrain()->GetHeight() - 2, terrainImages);
    Scene *scene = new Scene(horizonTexture, terrainTexture);
    AddFixedObjects(scene);
    for (unsigned int y = 1; y <= MAX_TILES; y++)
    {
        for (unsigned int x = 1; x <= MAX_TILES; x++)
        {
            AddTiledObjects(scene, x, y, terrainTexture);
        }
    }
    return scene;
}
