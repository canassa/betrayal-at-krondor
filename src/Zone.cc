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
 * Copyright (C) 2005-2008 Guido de Jong <guidoj@users.sf.net>
 */

#include <iomanip>
#include <sstream>

#include "Exception.h"
#include "FileManager.h"
#include "ScreenResource.h"
#include "Zone.h"

Zone::Zone()
        : horizon()
        , terrain(0)
        , sprites()
        , tiles()
        , table(0)
{}

Zone::~Zone()
{
    Clear();
}

void
Zone::Clear()
{
    for (unsigned int i = 0; i < sprites.size(); i++)
    {
        delete sprites[i];
    }
    sprites.clear();
    if (terrain)
    {
        delete terrain;
    }
    for (std::map<const std::pair<unsigned int, unsigned int>, TileWorldResource *>::iterator it = tiles.begin(); it != tiles.end(); ++it)
    {
        delete (*it).second;
    }
    tiles.clear();
    if (table)
    {
        delete table;
    }
}

void
Zone::Load(const unsigned int n)
{
    try
    {
        Clear();

        std::stringstream horizonStream;
        horizonStream << "Z" << std::setw(2) << std::setfill('0') << n << "H.BMX";
        FileManager::GetInstance()->Load(&horizon, horizonStream.str());

        static const int TERRAIN_IMAGE_WIDTH = 172;
        static const int TERRAIN_IMAGE_HEIGHT = 130;
        std::stringstream textureStream;
        textureStream << "Z" << std::setw(2) << std::setfill('0') << n << "L.SCX";
        ScreenResource textures;
        FileManager::GetInstance()->Load(&textures, textureStream.str());
        if (terrain)
        {
            delete terrain;
        }
        terrain = new Image(TERRAIN_IMAGE_WIDTH, TERRAIN_IMAGE_HEIGHT, textures.GetImage()->GetPixels());

        unsigned int i = 0;
        bool found = true;
        while (found)
        {
            std::stringstream spriteStream;
            spriteStream << "Z" << std::setw(2) << std::setfill('0') << n << "SLOT" << std::setw(1) << i << ".BMX";
            found = FileManager::GetInstance()->ResourceExists(spriteStream.str());
            if (found)
            {
                ImageResource spriteSlot;
                FileManager::GetInstance()->Load(&spriteSlot, spriteStream.str());
                for (unsigned int j = 0; j < spriteSlot.GetNumImages(); j++)
                {
                    Image *img = new Image(spriteSlot.GetImage(j));
                    sprites.push_back(img);
                }
                i++;
            }
        }

        for (unsigned int y = 1; y <= MAX_TILES; y++)
        {
            for (unsigned int x = 1; x <= MAX_TILES; x++)
            {
                std::stringstream tileStream;
                tileStream << "T" << std::setw(2) << std::setfill('0') << n
                           << std::setw(2) << std::setfill('0') << x
                           << std::setw(2) << std::setfill('0') << y << ".WLD";
                if (FileManager::GetInstance()->ResourceExists(tileStream.str()))
                {
                    TileWorldResource *tile = new TileWorldResource;
                    FileManager::GetInstance()->Load(tile, tileStream.str());
                    std::pair<unsigned int, unsigned int> coord(x, y);
                    tiles.insert(std::pair<const std::pair<unsigned int, unsigned int>, TileWorldResource *>(coord, tile));
                }
            }
        }

        std::stringstream tableStream;
        tableStream << "Z" << std::setw(2) << std::setfill('0') << n << ".TBL";
        table = new TableResource;
        FileManager::GetInstance()->Load(table, tableStream.str());
    }
    catch (Exception &e)
    {
        e.Print("Zone::Load");
        throw;
    }
}

Image *
Zone::GetHorizon(const unsigned int n)
{
    return horizon.GetImage(n);
}

Image *
Zone::GetTerrain() const
{
    return terrain;
}

Image *
Zone::GetSprite(const unsigned int n)
{
    if (n < sprites.size())
    {
        return sprites[n];
    }
    else
    {
        throw IndexOutOfRange(__FILE__, __LINE__);
    }
}

TileWorldResource *
Zone::GetTile(const unsigned int x, const unsigned int y)
{
    std::pair<unsigned int, unsigned int> coord(x, y);
    std::map<const std::pair<unsigned int, unsigned int>, TileWorldResource *>::iterator it = tiles.find(coord);
    if (it != tiles.end())
    {
        return it->second;
    }
    return 0;
}

TableResource *
Zone::GetTable()
{
    return table;
}
