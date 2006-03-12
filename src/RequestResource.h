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

#ifndef REQUEST_RESOURCE_H
#define REQUEST_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Resource.h"

static const unsigned int REQ_SELECT = 4;
static const unsigned int REQ_BUTTON = 6;

static const unsigned int OPT0_CONTENTS    = 46;
static const unsigned int OPT0_NEW_GAME    = 49;
static const unsigned int OPT0_PREFERENCES = 25;
static const unsigned int OPT0_QUIT        = 32;
static const unsigned int OPT0_RESTORE     = 19;

static const unsigned int OPT1_CANCEL      = 18;
static const unsigned int OPT1_CONTENTS    = 46;
static const unsigned int OPT1_NEWGAME     = 49;
static const unsigned int OPT1_PREFERENCES = 25;
static const unsigned int OPT1_QUIT        = 32;
static const unsigned int OPT1_RESTORE     = 19;
static const unsigned int OPT1_SAVE        = 31;

typedef struct _RequestData {
  unsigned int widget;
  int action;
  bool visible;
  int xpos;
  int ypos;
  int width;
  int height;
  int teleport;
  std::string label;
} RequestData;

class RequestResource: public Resource {
  private:
    bool popup;
    int xpos;
    int ypos;
    int width;
    int height;
    int xoff;
    int yoff;
    std::vector<RequestData> data;
  public:
    RequestResource();
    virtual ~RequestResource();
    bool IsPopup() const;
    int GetXPos() const;
    int GetYPos() const;
    int GetWidth() const;
    int GetHeight() const;
    int GetXOff() const;
    int GetYOff() const;
    unsigned int GetSize() const;
    RequestData GetRequestData(const unsigned int n) const;
    void Load(FileBuffer *buffer);
};

#endif
