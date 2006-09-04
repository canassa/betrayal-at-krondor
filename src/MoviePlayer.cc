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
 * Copyright (C) 2005-2006  Guido de Jong <guidoj@users.sf.net>
 */

#include "Exception.h"
#include "FileManager.h"
#include "MousePointerManager.h"
#include "MoviePlayer.h"

static const unsigned int SAVE_BACKGROUND    = 0x0020;
static const unsigned int DRAW_BACKGROUND    = 0x0080;
static const unsigned int END_OF_PAGE        = 0x0ff0;
static const unsigned int DELAY              = 0x1020;
static const unsigned int SLOT_IMAGE         = 0x1050;
static const unsigned int SLOT_PALETTE       = 0x1060;
static const unsigned int SET_SCENE          = 0x1110;
static const unsigned int SET_FRAME0         = 0x2000;
static const unsigned int SET_FRAME1         = 0x2010;
static const unsigned int FADE_OUT           = 0x4110;
static const unsigned int FADE_IN            = 0x4120;
static const unsigned int DRAW_WINDOW        = 0xa100;
static const unsigned int DRAW_SPRITE0       = 0xa500;
static const unsigned int DRAW_SPRITE1       = 0xa510;
static const unsigned int DRAW_SPRITE2       = 0xa520;
static const unsigned int DRAW_SPRITE3       = 0xa530;
static const unsigned int READ_IMAGE         = 0xb600;
static const unsigned int LOAD_SOUNDRESOURCE = 0xc020;
static const unsigned int SELECT_SOUND       = 0xc030;
static const unsigned int DESELECT_SOUND     = 0xc040;
static const unsigned int PLAY_SOUND         = 0xc050;
static const unsigned int STOP_SOUND         = 0xc060;
static const unsigned int LOAD_SCREEN        = 0xf010;
static const unsigned int LOAD_IMAGE         = 0xf020;
static const unsigned int LOAD_PALETTE       = 0xf050;

MoviePlayer::MoviePlayer(MediaToolkit *mtk)
: media(mtk)
{
  media->AddKeyboardListener(this);
  media->AddMouseButtonListener(this);
  media->AddTimerListener(this);
  media->AddUpdateListener(this);
}

MoviePlayer::~MoviePlayer()
{
  media->RemoveKeyboardListener(this);
  media->RemoveMouseButtonListener(this);
  media->RemoveTimerListener(this);
  media->RemoveUpdateListener(this);
}

void
MoviePlayer::Play(std::vector<MovieTag *> *movie, const bool repeat) {
  try {
    tagVec = movie;
    looped = repeat;
    delayed = false;
    screenSlot = 0;
    soundSlot = SoundResource::GetInstance();
    memset(imageSlot, 0, sizeof(ImageResource*) * MAX_IMAGE_SLOTS);
    memset(paletteSlot, 0, sizeof(PaletteResource*) * MAX_PALETTE_SLOTS);
    backgroundImage = 0;
    backgroundImageDrawn = false;
    savedImage = 0;
    savedImageDrawn = false;
    currFrame = 0;
    currImage = 0;
    currPalette = 0;
    currTag = 0;
    currDelay = 0;
    currSound = 0;
    soundMap.clear();
    paletteSlot[currPalette] = new PaletteResource;
    paletteSlot[currPalette]->Retrieve(media->GetVideo(), 0, VIDEO_COLORS);
    paletteActivated = false;

    MousePointerManager::GetInstance()->GetCurrentPointer()->SetVisible(false);
    media->ClearEvents();
    media->PollEventLoop();

    (paletteSlot[currPalette])->FadeOut(media, 0, VIDEO_COLORS, 64, 5);
    if (screenSlot) {
      delete screenSlot;
    }
    for (unsigned int i = 0; i < MAX_IMAGE_SLOTS; i++) {
      if (imageSlot[i]) {
        delete imageSlot[i];
      }
    }
    for (unsigned int i = 0; i < MAX_PALETTE_SLOTS; i++) {
      if (paletteSlot[i]) {
        delete paletteSlot[i];
      }
    }
    if (backgroundImage) {
      delete backgroundImage;
    }
    if (savedImage) {
      delete savedImage;
    }
  } catch (Exception &e) {
    e.Print("MoviePlayer::Play");
    throw;
  }
}

void
MoviePlayer::KeyPressed(const KeyboardEvent& kbe) {
  switch (kbe.GetKey()) {
    case KEY_ESCAPE:
    case KEY_RETURN:
    case KEY_SPACE:
      media->TerminateEventLoop();
      break;
    default:
      break;
  }
}

void
MoviePlayer::KeyReleased(const KeyboardEvent& kbe) {
  switch (kbe.GetKey()) {
    default:
      break;
  }
}

void
MoviePlayer::MouseButtonPressed(const MouseButtonEvent& mbe) {
  switch (mbe.GetButton()) {
    case MB_LEFT:
      media->TerminateEventLoop();
      break;
    default:
      break;
  }
}

void
MoviePlayer::MouseButtonReleased(const MouseButtonEvent& mbe) {
  switch (mbe.GetButton()) {
    default:
      break;
  }
}

void
MoviePlayer::TimerExpired(const TimerEvent& te) {
  if (te.GetID() == TMR_MOVIE_PLAYER) {
    delayed = false;
  }
}

void
MoviePlayer::Update(const UpdateEvent& ue) {
  ue.GetTicks();
  if (delayed) return;
  try {
    MovieTag *mt = (*tagVec)[currTag];
    switch (mt->code) {
      case SAVE_BACKGROUND:
        if (!backgroundImage) {
          backgroundImage = new Image(VIDEO_WIDTH, VIDEO_HEIGHT);
        }
        backgroundImage->Read(media->GetVideo(), 0, 0);
        break;
      case DRAW_BACKGROUND:
        if (backgroundImage) {
          backgroundImage->Draw(media->GetVideo(), 0, 0);
          backgroundImageDrawn = true;
        }
        break;
      case END_OF_PAGE:
        if (!paletteActivated) {
          paletteSlot[currPalette]->Activate(media->GetVideo(), 0, VIDEO_COLORS);
          paletteActivated = true;
        }
        media->GetVideo()->Refresh();
        if (currDelay > 0) {
          delayed = true;
          media->GetClock()->StartTimer(TMR_MOVIE_PLAYER, currDelay);
        }
        backgroundImageDrawn = false;
        savedImageDrawn = false;
        break;
      case DELAY:
        currDelay = mt->data[0] * 10;
        break;
      case SLOT_IMAGE:
        currImage = mt->data[0];
        break;
      case SLOT_PALETTE:
        currPalette = mt->data[0];
        paletteActivated = false;
        break;
      case SET_SCENE:
        break;
      case SET_FRAME0:
      case SET_FRAME1:
        currFrame = mt->data[1];
        break;
      case FADE_OUT:
        (paletteSlot[currPalette])->FadeOut(media, mt->data[0], mt->data[1], 64 << (mt->data[2] & 0x0f), 2 << mt->data[3]);
        media->GetVideo()->Clear();
        paletteActivated = true;
        break;
      case FADE_IN:
        (paletteSlot[currPalette])->FadeIn(media, mt->data[0], mt->data[1], 64 << (mt->data[2] & 0x0f), 2 << mt->data[3]);
        paletteActivated = true;
        break;
      case DRAW_WINDOW:
        if ((backgroundImage) && (!backgroundImageDrawn)) {
          backgroundImage->Draw(media->GetVideo(), 0, 0);
          backgroundImageDrawn = true;
        }
        if (imageSlot[currImage]) {
          (imageSlot[currImage])->GetImage(currFrame)->Draw(media->GetVideo(), mt->data[0], mt->data[1], 0, 0, mt->data[2], mt->data[3]);
        }
        break;
      case DRAW_SPRITE3:
        if ((currDelay > 0) && (!delayed)) {
          delayed = true;
          media->GetClock()->StartTimer(TMR_MOVIE_PLAYER, 3 * currDelay);
        }
      case DRAW_SPRITE2:
        if ((currDelay > 0) && (!delayed)) {
          delayed = true;
          media->GetClock()->StartTimer(TMR_MOVIE_PLAYER, 2 * currDelay);
        }
      case DRAW_SPRITE1:
        if ((currDelay > 0) && (!delayed)) {
          delayed = true;
          media->GetClock()->StartTimer(TMR_MOVIE_PLAYER, currDelay);
        }
      case DRAW_SPRITE0:
        if ((backgroundImage) && (!backgroundImageDrawn)) {
          backgroundImage->Draw(media->GetVideo(), 0, 0);
          backgroundImageDrawn = true;
        }
        if ((savedImage) && (!savedImageDrawn)) {
          savedImage->Draw(media->GetVideo(), 0, 0);
          savedImageDrawn = true;
        }
        if (imageSlot[mt->data[3]]) {
          (imageSlot[mt->data[3]])->GetImage(mt->data[2])->Draw(media->GetVideo(), mt->data[0], mt->data[1], 0);
        }
        break;
      case READ_IMAGE:
        if (savedImage) {
          delete savedImage;
        }
        savedImage = new Image(mt->data[2], mt->data[3]);
        savedImage->Read(media->GetVideo(), mt->data[0], mt->data[1]);
        savedImageDrawn = false;
        break;
      case LOAD_SOUNDRESOURCE:
        break;
      case SELECT_SOUND:
        {
          std::map<unsigned int, int>::iterator it = soundMap.find(mt->data[0]);
          if (it != soundMap.end()) {
            if (it->second >= 0) {
              media->GetAudio()->StopSound(it->second);
            }
            soundMap.erase(it);
          }
          soundMap.insert(std::pair<unsigned int, int>(mt->data[0], -1));
        }
        break;
      case DESELECT_SOUND:
        {
          std::map<unsigned int, int>::iterator it = soundMap.find(mt->data[0]);
          if (it != soundMap.end()) {
            if (it->second >= 0) {
              media->GetAudio()->StopSound(it->second);
            }
            soundMap.erase(it);
          }
        }
        break;
      case PLAY_SOUND:
        {
          std::map<unsigned int, int>::iterator it = soundMap.find(mt->data[0]);
          if (it != soundMap.end()) {
            if (it->second >= 0) {
              media->GetAudio()->StopSound(it->second);
            }
            SoundData data = soundSlot->GetSoundData(it->first);
            it->second = media->GetAudio()->PlaySound(data.sounds[0]->GetSamples());
          }
        }
        break;
      case STOP_SOUND:
        {
          std::map<unsigned int, int>::iterator it = soundMap.find(mt->data[0]);
          if (it != soundMap.end()) {
            if (it->second >= 0) {
              media->GetAudio()->StopSound(it->second);
            }
            soundMap.erase(it);
          }
        }
        break;
      case LOAD_SCREEN:
        if (screenSlot) {
          delete screenSlot;
        }
        mt->name[mt->name.length() - 1] = 'X';
        screenSlot = new ScreenResource;
        FileManager::GetInstance()->Load(screenSlot, mt->name);
        screenSlot->GetImage()->Draw(media->GetVideo(), 0, 0);
        break;
      case LOAD_IMAGE:
        if (imageSlot[currImage]) {
          delete imageSlot[currImage];
        }
        mt->name[mt->name.length() - 1] = 'X';
        imageSlot[currImage] = new ImageResource;
        FileManager::GetInstance()->Load(imageSlot[currImage], mt->name);
        break;
      case LOAD_PALETTE:
        if (paletteSlot[currPalette]) {
          delete paletteSlot[currPalette];
        }
        paletteSlot[currPalette] = new PaletteResource;
        FileManager::GetInstance()->Load(paletteSlot[currPalette], mt->name);
        paletteActivated = false;
        break;
      default:
        break;
    }
    currTag++;
    if (currTag == tagVec->size()) {
      if (looped) {
        currTag = 0;
        if (backgroundImage) {
          delete backgroundImage;
          backgroundImage = 0;
        }
        if (savedImage) {
          delete savedImage;
          savedImage = 0;
        }
      } else {
        media->TerminateEventLoop();
      }
    }
  } catch (Exception &e) {
    e.Print("MoviePlayer::Update");
    throw;
  }
}
