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

#ifndef DIALOG_FACTORY_H
#define DIALOG_FACTORY_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <vector>

#include "Dialog.h"
#include "PaletteResource.h"
#include "WidgetFactory.h"

class DialogFactory
{
private:
    RequestResource request;
    PaletteResource palette;
    ScreenResource screen;
    ImageResource normal;
    ImageResource pressed;
    ImageResource heads;
    ImageResource compass;
    ImageResource icons;
    ImageResource images;
    FontResource font;
    LabelResource label;
    WidgetFactory widgetFactory;
public:
    DialogFactory();
    virtual ~DialogFactory();
    Dialog* CreateCampDialog();
    Dialog* CreateCastDialog();
    Dialog* CreateContentsDialog();
    Dialog* CreateFullMapDialog();
    Dialog* CreateInfoDialog();
    Dialog* CreateInventoryDialog();
    Dialog* CreateLoadDialog();
    Dialog* CreateMapDialog();
    Dialog* CreateOptionsDialog ( const bool firstTime );
    Dialog* CreatePreferencesDialog();
    Dialog* CreateSaveDialog();
    Dialog* CreateWorldDialog();
};

#endif
