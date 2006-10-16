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

#include "ResourceData.h"

static const unsigned int REQ_USERDEFINED   = 0;
static const unsigned int REQ_IMAGEBUTTON   = 3;
static const unsigned int REQ_SELECT        = 4;
static const unsigned int REQ_TEXTBUTTON    = 6;

static const unsigned int ACT_ESCAPE        = 512;
static const unsigned int ACT_UP            = 513;
static const unsigned int ACT_DOWN          = 514;
static const unsigned int ACT_LEFT          = 515;
static const unsigned int ACT_RIGHT         = 516;

static const unsigned int CAMP_EXIT         = 192;
static const unsigned int CAMP_UNTIL_HEALED = 193;
static const unsigned int CAMP_STOP         = 194;

static const unsigned int CAST_TRIANGLE     = 7;
static const unsigned int CAST_SQUARE       = 6;
static const unsigned int CAST_CAST         = 2;
static const unsigned int CAST_BOOKMARK     = 3;
static const unsigned int CAST_CAMP1        = 4;
static const unsigned int CAST_CAMP2        = 5;
static const unsigned int CAST_EXIT         = 1;
static const unsigned int CAST_MEMBER1      = 128;
static const unsigned int CAST_MEMBER2      = 129;
static const unsigned int CAST_MEMBER3      = 130;

static const unsigned int CONT_EXIT         = 1;

static const unsigned int FMAP_EXIT         = 18;

static const unsigned int INV_MEMBER1       = 2;
static const unsigned int INV_MEMBER2       = 3;
static const unsigned int INV_MEMBER3       = 4;
static const unsigned int INV_UNKNOWN       = 22;
static const unsigned int INV_EXIT          = 1;
static const unsigned int INV_MORE_INFO     = 57;

static const unsigned int LOAD_RESTORE      = 193;
static const unsigned int LOAD_CANCEL       = 192;

static const unsigned int MAIN_LEFT         = 75;
static const unsigned int MAIN_UP           = 72;
static const unsigned int MAIN_DOWN         = 80;
static const unsigned int MAIN_RIGHT        = 77;
static const unsigned int MAIN_UNKNOWN      = 19;
static const unsigned int MAIN_MAP          = 50;
static const unsigned int MAIN_CAST         = 46;
static const unsigned int MAIN_BOOKMARK     = 48;
static const unsigned int MAIN_CAMP         = 18;
static const unsigned int MAIN_OPTIONS      = 24;
static const unsigned int MAIN_MEMBER1      = 2;
static const unsigned int MAIN_MEMBER2      = 3;
static const unsigned int MAIN_MEMBER3      = 4;

static const unsigned int MAP_LEFT          = 75;
static const unsigned int MAP_UP            = 72;
static const unsigned int MAP_DOWN          = 80;
static const unsigned int MAP_RIGHT         = 77;
static const unsigned int MAP_UNKNOWN       = 19;
static const unsigned int MAP_FULLMAP       = 33;
static const unsigned int MAP_ZOOMOUT       = 73;
static const unsigned int MAP_ZOOMIN        = 81;
static const unsigned int MAP_CAMP          = 18;
static const unsigned int MAP_MAIN          = 50;
static const unsigned int MAP_MEMBER1       = 2;
static const unsigned int MAP_MEMBER2       = 3;
static const unsigned int MAP_MEMBER3       = 4;

static const unsigned int OPT_CANCEL        = 18;
static const unsigned int OPT_CONTENTS      = 46;
static const unsigned int OPT_NEW_GAME      = 49;
static const unsigned int OPT_PREFERENCES   = 25;
static const unsigned int OPT_QUIT          = 32;
static const unsigned int OPT_RESTORE       = 19;
static const unsigned int OPT_SAVE          = 31;

static const unsigned int PREF_CANCEL       = 46;
static const unsigned int PREF_DEFAULTS     = 32;
static const unsigned int PREF_OK           = 24;

static const unsigned int SAVE_REMOVE_DIR   = 195;
static const unsigned int SAVE_REMOVE_GAME  = 194;
static const unsigned int SAVE_SAVE         = 193;
static const unsigned int SAVE_CANCEL       = 192;

static const int GROUP0 = 0;
static const int GROUP1 = 1;
static const int GROUP2 = 2;
static const int GROUP3 = 3;

typedef struct _RequestData {
  unsigned int widget;
  int action;
  bool visible;
  int xpos;
  int ypos;
  int width;
  int height;
  int teleport;
  int image;
  int group;
  std::string label;
} RequestData;

class RequestResource
: public ResourceData {
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
    void Clear();
    void Load(FileBuffer *buffer);
};

#endif
