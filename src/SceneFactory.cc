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

#include "MeshedObject.h"
#include "SceneFactory.h"
#include "SpritedObject.h"
#include "TerrainObject.h"

SceneFactory::SceneFactory()
{
}

SceneFactory::~SceneFactory()
{
}

Scene *
SceneFactory::CreateScene(Zone& zone)
{
  Scene *scene = new Scene(zone);
  TableResource *table = zone.GetTable();
  for (unsigned int y = 1; y <= MAX_TILES; y++) {
    for (unsigned int x = 1; x <= MAX_TILES; x++) {
      TileWorldResource *tile = zone.GetTile(x, y);
      if (tile) {
        for (unsigned int i = 0; i < tile->GetSize(); i++) {
          TileWorldItem item = tile->GetItem(i);
          DatInfo dat = table->GetDatItem(item.type);
          GidInfo gid = table->GetGidItem(item.type);
          switch (dat.objectType) {
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
              scene->AddObject(new SpritedObject(item.xloc, item.yloc, gid.xsize, gid.ysize, zone.GetSprite(dat.sprite)));
              break;
            default:
              break;
          }
        }
      }
    }
  }
  return scene;
}
