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

#include "Exception.h"
#include "FileManager.h"
#include "Game.h"
#include "ObjectResource.h"
#include "PlayerCharacter.h"
#include "SceneFactory.h"

Game::Game()
        : name("")
        , chapter(0)
        , party(0)
        , scene(0)
        , camera(0)
{
    try
    {
        FileManager::GetInstance()->Load(&partyRes, "PARTY.DAT");
        FileManager::GetInstance()->Load(&buttonImages, "HEADS.BMX");
        chapter = new Chapter(1);
        party = new Party;
        for (unsigned int i = 0; i < partyRes.GetSize(); i++)
        {
            PartyData *pd = partyRes.GetData(i);
            PlayerCharacter *pc = new PlayerCharacter(pd->name);
            pc->SetButtonImage(buttonImages.GetImage(i));
            party->AddMember(pc);
        }
        SceneFactory sf(chapter->GetZone());
        scene = sf.CreateScene();
        camera = new Camera(Vector2D(0, 0), 0);
    }
    catch (Exception &e)
    {
        e.Print("Game::Game");
        throw;
    }
}

Game::~Game()
{
    if (camera)
    {
        delete camera;
    }
    if (scene)
    {
        delete scene;
    }
    if (party)
    {
        delete party;
    }
    if (chapter)
    {
        delete chapter;
    }
}

std::string&
Game::GetName()
{
    return name;
}

void
Game::SetName(const std::string& s)
{
    name = s;
}

Party *
Game::GetParty() const
{
    return party;
}

Chapter *
Game::GetChapter() const
{
    return chapter;
}

Camera *
Game::GetCamera() const
{
    return camera;
}

Scene *
Game::GetScene() const
{
    return scene;
}
