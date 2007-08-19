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
 * Copyright (C) 2005-2007  Guido de Jong <guidoj@users.sf.net>
 */

#ifndef STATISTICS_H
#define STATISTICS_H

#ifdef HAVE_CONFIG
#include "config.h"
#endif

static const unsigned int STAT_HEALTH            =  0;
static const unsigned int STAT_STAMINA           =  1;
static const unsigned int STAT_SPEED             =  2;
static const unsigned int STAT_STRENGTH          =  3;
static const unsigned int STAT_DEFENSE           =  4;
static const unsigned int STAT_CROSSBOW_ACCURACY =  5;
static const unsigned int STAT_MELEE_ACCURACY    =  6;
static const unsigned int STAT_CASTING_ACCURACY  =  7;
static const unsigned int STAT_ASSESSMENT        =  8;
static const unsigned int STAT_ARMORCRAFT        =  9;
static const unsigned int STAT_WEAPONCRAFT       = 10;
static const unsigned int STAT_BARDING           = 11;
static const unsigned int STAT_HAGGLING          = 12;
static const unsigned int STAT_LOCKPICK          = 13;
static const unsigned int STAT_SCOUTING          = 14;
static const unsigned int STAT_STEALTH           = 15;
static const unsigned int NUM_STATS              = 16;

static const unsigned int STAT_MAXIMUM    = 0;
static const unsigned int STAT_CURRENT    = 1;
static const unsigned int STAT_ACTUAL     = 2;
static const unsigned int STAT_EXPERIENCE = 3;
static const unsigned int STAT_MODIFIER   = 4;
static const unsigned int NUM_STAT_VALUES = 5;

typedef int StatValues[NUM_STAT_VALUES];

class Statistics
{
private:
    StatValues statMatrix[NUM_STATS];
public:
    Statistics();
    virtual ~Statistics();
    int Get ( const unsigned int stat, const unsigned int type ) const;
    void Set ( const unsigned int stat, const unsigned int type, const unsigned int value );
};

#endif
