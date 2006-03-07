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
#include "MousePointerManager.h"
#include "MoviePlayer.h"
#include "ResourceManager.h"

static const unsigned int SAVE_DISPLAY      = 0x0020;
static const unsigned int DRAW_SAVED_IMAGE  = 0x0080;
static const unsigned int END_OF_PAGE       = 0x0ff0;
static const unsigned int DELAY             = 0x1020;
static const unsigned int SLOT_IMAGE        = 0x1050;
static const unsigned int SLOT_PALETTE      = 0x1060;
static const unsigned int SET_SCENE         = 0x1110;
static const unsigned int SET_FRAME0        = 0x2000;
static const unsigned int SET_FRAME1        = 0x2010;
static const unsigned int FADE_OUT          = 0x4110;
static const unsigned int FADE_IN           = 0x4120;
static const unsigned int DRAW_WINDOW       = 0xa100;
static const unsigned int DRAW_SPRITE0      = 0xa500;
static const unsigned int DRAW_SPRITE1      = 0xa510;
static const unsigned int DRAW_SPRITE2      = 0xa520;
static const unsigned int DRAW_SPRITE3      = 0xa530;
static const unsigned int READ_IMAGE        = 0xb600;
static const unsigned int LOAD_SCREEN       = 0xf010;
static const unsigned int LOAD_IMAGE        = 0xf020;
static const unsigned int LOAD_PALETTE      = 0xf050;

MoviePlayer::MoviePlayer(MediaToolkit *mtk)
: media(mtk)
{
  media->AddKeyboardListener(this);
  media->AddMouseButtonListener(this);
  media->AddUpdateListener(this);
}

MoviePlayer::~MoviePlayer()
{
  media->RemoveKeyboardListener(this);
  media->RemoveMouseButtonListener(this);
  media->RemoveUpdateListener(this);
}

void
MoviePlayer::Play(std::vector<MovieTag *> *movie, const bool repeat) {
  try {
    tagVec = movie;
    looped = repeat;
    screenSlot = 0;
    memset(imageSlot, 0, sizeof(ImageResource*) * MAX_IMAGE_SLOTS);
    memset(paletteSlot, 0, sizeof(PaletteResource*) * MAX_PALETTE_SLOTS);
    savedImage = 0;
    savedImageDrawn = false;
    currFrame = 0;
    currImage = 0;
    currPalette = 0;
    currTag = 0;
    currDelay = 0;
    paletteSlot[currPalette] = new PaletteResource;
    paletteSlot[currPalette]->Retrieve(media->GetVideo(), 0, VIDEO_COLORS);
    paletteActivated = false;

    MousePointerManager::GetInstance()->GetCurrentPointer()->SetVisible(false);
    media->ClearEvents();
    media->PollEventLoop();

    (paletteSlot[currPalette])->FadeOut(media->GetVideo(), 0, VIDEO_COLORS, 64, 10, media->GetClock());
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
//      media->TerminateEventLoop();
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
MoviePlayer::Update(const UpdateEvent& ue) {
  ue.GetTicks();
  try {
    MovieTag *mt = (*tagVec)[currTag];
    switch (mt->code) {
      case SAVE_DISPLAY:
        if (!savedImage) {
          savedImage = new Image(VIDEO_WIDTH, VIDEO_HEIGHT);
        }
        savedImage->Read(media->GetVideo(), 0, 0);
        break;
      case DRAW_SAVED_IMAGE:
        if (savedImage) {
          savedImage->Draw(media->GetVideo(), 0, 0);
          savedImageDrawn = true;
        }
        break;
      case END_OF_PAGE:
        if (!paletteActivated) {
          paletteSlot[currPalette]->Activate(media->GetVideo(), 0, VIDEO_COLORS);
          paletteActivated = true;
        }
        media->GetVideo()->Refresh();
        media->GetClock()->Delay(currDelay);
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
        currImage = mt->data[0];
        currFrame = mt->data[1];
        break;
      case FADE_OUT:
        (paletteSlot[currPalette])->FadeOut(media->GetVideo(), mt->data[0], mt->data[1], 64 << (mt->data[2] & 0x0f), 2 << mt->data[3], media->GetClock());
        paletteActivated = true;
        break;
      case FADE_IN:
        (paletteSlot[currPalette])->FadeIn(media->GetVideo(), mt->data[0], mt->data[1], 64 << (mt->data[2] & 0x0f), 2 << mt->data[3], media->GetClock());
        paletteActivated = true;
        break;
      case DRAW_WINDOW:
        (imageSlot[currImage])->GetImage(currFrame)->Draw(media->GetVideo(), mt->data[0], mt->data[1], 0, 0, mt->data[2], mt->data[3]);
        break;
      case DRAW_SPRITE3:
        media->GetClock()->Delay(currDelay);
      case DRAW_SPRITE2:
        media->GetClock()->Delay(currDelay);
      case DRAW_SPRITE1:
        media->GetClock()->Delay(currDelay);
      case DRAW_SPRITE0:
        if ((savedImage) && (!savedImageDrawn)) {
          savedImage->Draw(media->GetVideo(), 0, 0);
          savedImageDrawn = true;
        }
        (imageSlot[mt->data[3]])->GetImage(mt->data[2])->Draw(media->GetVideo(), mt->data[0], mt->data[1], 0);
        break;
      case READ_IMAGE:
        if (savedImage) {
          delete savedImage;
          savedImage = 0;
        }
        savedImage = new Image(mt->data[2], mt->data[3]);
        savedImage->Read(media->GetVideo(), mt->data[0], mt->data[1]);
        savedImageDrawn = false;
        break;
      case LOAD_SCREEN:
        if (screenSlot) {
          delete screenSlot;
        }
        mt->name[mt->name.length() - 1] = 'X';
        screenSlot = new ScreenResource;
        ResourceManager::GetInstance()->Load(screenSlot, mt->name);
        screenSlot->GetImage()->Draw(media->GetVideo(), 0, 0);
        break;
      case LOAD_IMAGE:
        if (imageSlot[currImage]) {
          delete imageSlot[currImage];
        }
        mt->name[mt->name.length() - 1] = 'X';
        imageSlot[currImage] = new ImageResource;
        ResourceManager::GetInstance()->Load(imageSlot[currImage], mt->name);
        break;
      case LOAD_PALETTE:
        if (paletteSlot[currPalette]) {
          delete paletteSlot[currPalette];
        }
        paletteSlot[currPalette] = new PaletteResource;
        ResourceManager::GetInstance()->Load(paletteSlot[currPalette], mt->name);
        paletteActivated = false;
        break;
      default:
        break;
    }
    currTag++;
    if (currTag == tagVec->size()) {
      if (looped) {
        currTag = 0;
      } else {
        media->TerminateEventLoop();
      }
    }
  } catch (Exception &e) {
    e.Print("MoviePlayer::Update");
    throw;
  }
}
