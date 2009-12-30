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
 * Copyright (C) 2005-2009 Guido de Jong <guidoj@users.sf.net>
 */

#include <cstring>

#include "Exception.h"
#include "FileManager.h"
#include "MoviePlayer.h"
#include "PointerManager.h"

static const unsigned int SAVE_BACKGROUND    = 0x0020;
static const unsigned int DRAW_BACKGROUND    = 0x0080;
static const unsigned int UPDATE             = 0x0ff0;
static const unsigned int DELAY              = 0x1020;
static const unsigned int SLOT_IMAGE         = 0x1050;
static const unsigned int SLOT_PALETTE       = 0x1060;
static const unsigned int SET_SCENE          = 0x1110;
static const unsigned int SET_FRAME0         = 0x2000;
static const unsigned int SET_FRAME1         = 0x2010;
static const unsigned int FADE_OUT           = 0x4110;
static const unsigned int FADE_IN            = 0x4120;
static const unsigned int DRAW_IMAGE         = 0xa100;
static const unsigned int DRAW_SPRITE0       = 0xa500;
static const unsigned int DRAW_SPRITE1       = 0xa510;
static const unsigned int DRAW_SPRITE2       = 0xa520;
static const unsigned int DRAW_SPRITE3       = 0xa530;
static const unsigned int DRAW_SCREEN        = 0xb600;
static const unsigned int LOAD_SOUNDRESOURCE = 0xc020;
static const unsigned int SELECT_SOUND       = 0xc030;
static const unsigned int DESELECT_SOUND     = 0xc040;
static const unsigned int PLAY_SOUND         = 0xc050;
static const unsigned int STOP_SOUND         = 0xc060;
static const unsigned int LOAD_SCREEN        = 0xf010;
static const unsigned int LOAD_IMAGE         = 0xf020;
static const unsigned int LOAD_PALETTE       = 0xf050;

MoviePlayer::MoviePlayer()
{
    MediaToolkit::GetInstance()->AddKeyboardListener(this);
    MediaToolkit::GetInstance()->AddPointerButtonListener(this);
    MediaToolkit::GetInstance()->AddTimerListener(this);
}

MoviePlayer::~MoviePlayer()
{
    MediaToolkit::GetInstance()->RemoveKeyboardListener(this);
    MediaToolkit::GetInstance()->RemovePointerButtonListener(this);
    MediaToolkit::GetInstance()->RemoveTimerListener(this);
}

void MoviePlayer::Play(std::vector<MovieChunk *> *movie, const bool repeat)
{
    try
    {
        chunkVec = movie;
        looped = repeat;
        delayed = false;
        playing = true;
        screenSlot = 0;
        soundSlot = SoundResource::GetInstance();
        memset(imageSlot, 0, sizeof(ImageResource*) * MAX_IMAGE_SLOTS);
        memset(paletteSlot, 0, sizeof(Palette*) * MAX_PALETTE_SLOTS);
        backgroundImage = 0;
        backgroundImageDrawn = false;
        currFrame = 0;
        currImage = 0;
        currPalette = 0;
        currChunk = 0;
        currDelay = 0;
        currSound = 0;
        soundMap.clear();
        paletteSlot[currPalette] = new PaletteResource;
        paletteSlot[currPalette]->GetPalette()->Retrieve(0, VIDEO_COLORS);
        paletteActivated = false;

        PointerManager::GetInstance()->GetCurrentPointer()->SetVisible(false);

        while (playing)
        {
            PlayChunk(MediaToolkit::GetInstance());
            if (playing)
            {
                MediaToolkit::GetInstance()->WaitEvents();
            }
        }
        if (delayed)
        {
            MediaToolkit::GetInstance()->GetClock()->CancelTimer(TMR_MOVIE_PLAYER);
        }
        paletteSlot[currPalette]->GetPalette()->FadeOut(0, VIDEO_COLORS, 64, 5);

        PointerManager::GetInstance()->GetCurrentPointer()->SetVisible(true);

        if (backgroundImage)
        {
            delete backgroundImage;
            backgroundImage = 0;
        }
        if (screenSlot)
        {
            delete screenSlot;
        }
        for (unsigned int i = 0; i < MAX_IMAGE_SLOTS; i++)
        {
            if (imageSlot[i])
            {
                delete imageSlot[i];
            }
        }
        for (unsigned int i = 0; i < MAX_PALETTE_SLOTS; i++)
        {
            if (paletteSlot[i])
            {
                delete paletteSlot[i];
            }
        }
    }
    catch (Exception &e)
    {
        e.Print("MoviePlayer::Play");
        throw;
    }
}

void MoviePlayer::PlayChunk(MediaToolkit* media)
{
    try
    {
        while ((playing) && (!delayed))
        {
            MovieChunk *mc = (*chunkVec)[currChunk];
            switch (mc->code)
            {
            case SAVE_BACKGROUND:
                if (!backgroundImage)
                {
                    backgroundImage = new Image(media->GetVideo()->GetWidth(), media->GetVideo()->GetHeight());
                }
                backgroundImage->Read(0, 0);
                break;
            case DRAW_BACKGROUND:
                if (backgroundImage)
                {
                    backgroundImage->Draw(0, 0);
                    backgroundImageDrawn = true;
                }
                break;
            case UPDATE:
                if (!paletteActivated)
                {
                    paletteSlot[currPalette]->GetPalette()->Activate(0, VIDEO_COLORS);
                    paletteActivated = true;
                }
                media->GetVideo()->Refresh();
                if (currDelay > 0)
                {
                    delayed = true;
                    media->GetClock()->StartTimer(TMR_MOVIE_PLAYER, currDelay);
                }
                backgroundImageDrawn = false;
                break;
            case DELAY:
                currDelay = mc->data[0] * 10;
                break;
            case SLOT_IMAGE:
                currImage = mc->data[0];
                break;
            case SLOT_PALETTE:
                currPalette = mc->data[0];
                paletteActivated = false;
                break;
            case SET_SCENE:
                break;
            case SET_FRAME0:
            case SET_FRAME1:
                currFrame = mc->data[1];
                break;
            case FADE_OUT:
                paletteSlot[currPalette]->GetPalette()->FadeOut(mc->data[0], mc->data[1], 64 << (mc->data[2] & 0x0f), 2 << mc->data[3]);
                media->GetVideo()->Clear();
                paletteActivated = true;
                break;
            case FADE_IN:
                paletteSlot[currPalette]->GetPalette()->FadeIn(mc->data[0], mc->data[1], 64 << (mc->data[2] & 0x0f), 2 << mc->data[3]);
                paletteActivated = true;
                break;
            case DRAW_IMAGE:
                if ((backgroundImage) && (!backgroundImageDrawn))
                {
                    backgroundImage->Draw(0, 0);
                    backgroundImageDrawn = true;
                }
                if (imageSlot[currImage])
                {
                    imageSlot[currImage]->GetImage(currFrame)->Draw(mc->data[0], mc->data[1], 0, 0, mc->data[2], mc->data[3]);
                }
                break;
            case DRAW_SPRITE3:
                if (currDelay > 0)
                {
                    media->GetClock()->Delay(currDelay);
                }
            case DRAW_SPRITE2:
                if (currDelay > 0)
                {
                    media->GetClock()->Delay(currDelay);
                }
            case DRAW_SPRITE1:
                if (currDelay > 0)
                {
                    media->GetClock()->Delay(currDelay);
                }
            case DRAW_SPRITE0:
                if ((backgroundImage) && (!backgroundImageDrawn))
                {
                    backgroundImage->Draw(0, 0);
                    backgroundImageDrawn = true;
                }
                if (imageSlot[mc->data[3]])
                {
                    imageSlot[mc->data[3]]->GetImage(mc->data[2])->Draw(mc->data[0], mc->data[1], 0);
                }
                break;
            case DRAW_SCREEN:
                if ((backgroundImage) && (!backgroundImageDrawn))
                {
                    backgroundImage->Draw(0, 0);
                    backgroundImageDrawn = true;
                }
                if (screenSlot)
                {
                    screenSlot->GetImage()->Draw(mc->data[0], mc->data[1]);
                }
                break;
            case LOAD_SOUNDRESOURCE:
                break;
            case SELECT_SOUND:
            {
                std::map<unsigned int, int>::iterator it = soundMap.find(mc->data[0]);
                if (it != soundMap.end())
                {
                    if (it->second >= 0)
                    {
                        media->GetAudio()->StopSound(it->second);
                    }
                    soundMap.erase(it);
                }
                soundMap.insert(std::pair<unsigned int, int>(mc->data[0], -1));
            }
            break;
            case DESELECT_SOUND:
            {
                std::map<unsigned int, int>::iterator it = soundMap.find(mc->data[0]);
                if (it != soundMap.end())
                {
                    if (it->second >= 0)
                    {
                        media->GetAudio()->StopSound(it->second);
                    }
                    soundMap.erase(it);
                }
            }
            break;
            case PLAY_SOUND:
            {
                std::map<unsigned int, int>::iterator it = soundMap.find(mc->data[0]);
                if (it != soundMap.end())
                {
                    if (it->second >= 0)
                    {
                        media->GetAudio()->StopSound(it->second);
                    }
                    SoundData data = soundSlot->GetSoundData(it->first);
                    it->second = media->GetAudio()->PlaySound(data.sounds[0]->GetSamples());
                }
            }
            break;
            case STOP_SOUND:
            {
                std::map<unsigned int, int>::iterator it = soundMap.find(mc->data[0]);
                if (it != soundMap.end())
                {
                    if (it->second >= 0)
                    {
                        media->GetAudio()->StopSound(it->second);
                    }
                    soundMap.erase(it);
                }
            }
            break;
            case LOAD_SCREEN:
                if (screenSlot)
                {
                    delete screenSlot;
                }
                mc->name[mc->name.length() - 1] = 'X';
                screenSlot = new ScreenResource;
                FileManager::GetInstance()->Load(screenSlot, mc->name);
                screenSlot->GetImage()->Draw(0, 0);
                break;
            case LOAD_IMAGE:
                if (imageSlot[currImage])
                {
                    delete imageSlot[currImage];
                }
                mc->name[mc->name.length() - 1] = 'X';
                imageSlot[currImage] = new ImageResource;
                FileManager::GetInstance()->Load(imageSlot[currImage], mc->name);
                break;
            case LOAD_PALETTE:
                if (paletteSlot[currPalette])
                {
                    delete paletteSlot[currPalette];
                }
                paletteSlot[currPalette] = new PaletteResource;
                FileManager::GetInstance()->Load(paletteSlot[currPalette], mc->name);
                paletteActivated = false;
                break;
            default:
                break;
            }
            currChunk++;
            if (currChunk == chunkVec->size())
            {
                if (looped)
                {
                    currChunk = 0;
                    if (backgroundImage)
                    {
                        delete backgroundImage;
                        backgroundImage = 0;
                    }
                }
                else
                {
                    playing = false;
                }
            }
        }
    }
    catch (Exception &e)
    {
        e.Print("MoviePlayer::PlayChunk");
        throw;
    }
}

void MoviePlayer::KeyPressed(const KeyboardEvent& kbe)
{
    switch (kbe.GetKey())
    {
    case KEY_ESCAPE:
    case KEY_RETURN:
    case KEY_SPACE:
        playing = false;
        break;
    default:
        break;
    }
}

void MoviePlayer::KeyReleased(const KeyboardEvent& kbe)
{
    switch (kbe.GetKey())
    {
    default:
        break;
    }
}

void MoviePlayer::PointerButtonPressed(const PointerButtonEvent& pbe)
{
    switch (pbe.GetButton())
    {
    case PB_PRIMARY:
        playing = false;
        break;
    default:
        break;
    }
}

void MoviePlayer::PointerButtonReleased(const PointerButtonEvent& pbe)
{
    switch (pbe.GetButton())
    {
    default:
        break;
    }
}

void MoviePlayer::TimerExpired(const TimerEvent& te)
{
    if (te.GetID() == TMR_MOVIE_PLAYER)
    {
        delayed = false;
    }
}
