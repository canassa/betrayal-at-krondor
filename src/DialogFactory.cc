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

#include "DialogFactory.h"
#include "DialogWindow.h"
#include "Exception.h"
#include "FileManager.h"
#include "GameApplication.h"

#include <iomanip>
#include <sstream>

DialogFactory::DialogFactory()
{
}

DialogFactory::~DialogFactory()
{
}

Dialog *
DialogFactory::CreateCampDialog()
{
  try {
    FileManager::GetInstance()->Load(&request, "REQ_CAMP.DAT");
    FileManager::GetInstance()->Load(&palette, "OPTIONS.PAL");
    FileManager::GetInstance()->Load(&screen, "ENCAMP.SCX");
    FileManager::GetInstance()->Load(&normal, "BICONS1.BMX");
    FileManager::GetInstance()->Load(&pressed, "BICONS2.BMX");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new GameDialog(palette.GetPalette(), new DialogWindow(panel));
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_IMAGEBUTTON:
          if (data.visible) {
            data.xpos += request.GetXOff();
            data.ypos += request.GetYOff();
            ImageButtonWidget *button = widgetFactory.CreateImageButton(data, normal, pressed, dialog);
            panel->AddActiveWidget(button);
          }
          break;
        default:
          break;
      }
    }
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateCampDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreateCastDialog()
{
  try {
    FileManager::GetInstance()->Load(&request, "REQ_CAST.DAT");
    FileManager::GetInstance()->Load(&palette, "OPTIONS.PAL");
    FileManager::GetInstance()->Load(&screen, "FRAME.SCX");
    FileManager::GetInstance()->Load(&normal, "BICONS1.BMX");
    FileManager::GetInstance()->Load(&pressed, "BICONS2.BMX");
    FileManager::GetInstance()->Load(&heads, "HEADS.BMX");
    FileManager::GetInstance()->Load(&compass, "COMPASS.BMX");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new GameDialog(palette.GetPalette(), new DialogWindow(panel));
    unsigned int nextMember = 0;
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_USERDEFINED:
          if ((data.action >= 0) && (data.group == GROUP2)) {
            panel->AddActiveWidget(widgetFactory.CreateCharacterButton(data, GameApplication::GetInstance()->GetGame()->GetParty()->GetActiveMember(nextMember), heads, dialog));
            nextMember++;
          }
          break;
        case REQ_IMAGEBUTTON:
          if (data.visible) {
            data.xpos += request.GetXOff();
            data.ypos += request.GetYOff();
            panel->AddActiveWidget(widgetFactory.CreateImageButton(data, normal, pressed, dialog));
          }
          break;
        default:
          break;
      }
    }
    panel->AddWidget(widgetFactory.CreateCompass(GameApplication::GetInstance()->GetGame()->GetCamera(), compass.GetImage(0)));
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateCastDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreateContentsDialog()
{
  try {
    FileManager::GetInstance()->Load(&request, "CONTENTS.DAT");
    FileManager::GetInstance()->Load(&palette, "CONTENTS.PAL");
    FileManager::GetInstance()->Load(&screen, "CONT2.SCX");
    FileManager::GetInstance()->Load(&normal, "BICONS1.BMX");
    FileManager::GetInstance()->Load(&pressed, "BICONS2.BMX");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new OptionsDialog(palette.GetPalette(), new DialogWindow(panel));
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_IMAGEBUTTON:
          if (data.visible) {
            data.xpos += request.GetXOff();
            data.ypos += request.GetYOff();
            ImageButtonWidget *button = widgetFactory.CreateImageButton(data, normal, pressed, dialog);
            panel->AddActiveWidget(button);
          }
          break;
        default:
          break;
      }
    }
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateContentsDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreateFullMapDialog()
{
  try {
    FileManager::GetInstance()->Load(&request, "REQ_FMAP.DAT");
    FileManager::GetInstance()->Load(&palette, "FULLMAP.PAL");
    FileManager::GetInstance()->Load(&screen, "FULLMAP.SCX");
    FileManager::GetInstance()->Load(&normal, "BICONS1.BMX");
    FileManager::GetInstance()->Load(&pressed, "BICONS2.BMX");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new GameDialog(palette.GetPalette(), new DialogWindow(panel));
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_IMAGEBUTTON:
          if (data.visible) {
            data.xpos += request.GetXOff();
            data.ypos += request.GetYOff();
            ImageButtonWidget *button = widgetFactory.CreateImageButton(data, normal, pressed, dialog);
            panel->AddActiveWidget(button);
          }
          break;
        default:
          break;
      }
    }
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateFullMapDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreateInventoryDialog()
{
  try {
    FileManager::GetInstance()->Load(&request, "REQ_INV.DAT");
    FileManager::GetInstance()->Load(&palette, "OPTIONS.PAL");
    FileManager::GetInstance()->Load(&screen, "INVENTOR.SCX");
    FileManager::GetInstance()->Load(&normal, "BICONS1.BMX");
    FileManager::GetInstance()->Load(&pressed, "BICONS2.BMX");
    FileManager::GetInstance()->Load(&font, "GAME.FNT");
    FileManager::GetInstance()->Load(&heads, "HEADS.BMX");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new GameDialog(palette.GetPalette(), new DialogWindow(panel));
    unsigned int nextMember = 0;
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_USERDEFINED:
          if ((data.action >= 0) && (data.group == GROUP3)) {
            panel->AddActiveWidget(widgetFactory.CreateCharacterButton(data, GameApplication::GetInstance()->GetGame()->GetParty()->GetActiveMember(nextMember), heads, dialog));
            nextMember++;
          }
          break;
        case REQ_IMAGEBUTTON:
          if (data.visible) {
            data.xpos += request.GetXOff();
            data.ypos += request.GetYOff();
            panel->AddActiveWidget(widgetFactory.CreateImageButton(data, normal, pressed, dialog));
          }
          break;
        case REQ_TEXTBUTTON:
          if (data.visible) {
            panel->AddActiveWidget(widgetFactory.CreateTextButton(data, font, dialog));
          }
          break;
        default:
          break;
      }
    }
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateInventoryDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreateLoadDialog()
{
  try {
    FileManager::GetInstance()->Load(&request, "REQ_LOAD.DAT");
    FileManager::GetInstance()->Load(&palette, "OPTIONS.PAL");
    FileManager::GetInstance()->Load(&screen, "OPTIONS2.SCX");
    FileManager::GetInstance()->Load(&font, "GAME.FNT");
    FileManager::GetInstance()->Load(&label, "LBL_LOAD.DAT");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new OptionsDialog(palette.GetPalette(), new DialogWindow(panel));
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_TEXTBUTTON:
          if (data.visible) {
            panel->AddActiveWidget(widgetFactory.CreateTextButton(data, font, dialog));
          }
          break;
        default:
          break;
      }
    }
    for (unsigned int i = 0; i < label.GetSize(); i++) {
      LabelData data = label.GetLabelData(i);
      panel->AddWidget(widgetFactory.CreateLabel(data, font, request.GetWidth() > screen.GetImage()->GetWidth() ? request.GetWidth() : screen.GetImage()->GetWidth()));
    }
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateLoadDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreateMapDialog()
{
  try {
    FileManager::GetInstance()->Load(&request, "REQ_MAP.DAT");
    FileManager::GetInstance()->Load(&palette, "OPTIONS.PAL");
    FileManager::GetInstance()->Load(&screen, "FRAME.SCX");
    FileManager::GetInstance()->Load(&normal, "BICONS1.BMX");
    FileManager::GetInstance()->Load(&pressed, "BICONS2.BMX");
    FileManager::GetInstance()->Load(&heads, "HEADS.BMX");
    FileManager::GetInstance()->Load(&compass, "COMPASS.BMX");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new GameDialog(palette.GetPalette(), new DialogWindow(panel));
    unsigned int nextMember = 0;
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_USERDEFINED:
          if ((data.action >= 0) && (data.group == GROUP2)) {
            panel->AddActiveWidget(widgetFactory.CreateCharacterButton(data, GameApplication::GetInstance()->GetGame()->GetParty()->GetActiveMember(nextMember), heads, dialog));
            nextMember++;
          }
          if ((data.action >= 0) && (data.group == GROUP3)) {
            panel->AddWidget(widgetFactory.CreateMapView(data, GameApplication::GetInstance()->GetGame()));
          }
          break;
        case REQ_IMAGEBUTTON:
          if (data.visible) {
            data.xpos += request.GetXOff();
            data.ypos += request.GetYOff();
            panel->AddActiveWidget(widgetFactory.CreateImageButton(data, normal, pressed, dialog));
          }
          break;
        default:
          break;
      }
    }
    panel->AddWidget(widgetFactory.CreateCompass(GameApplication::GetInstance()->GetGame()->GetCamera(), compass.GetImage(0)));
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateMapDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreateOptionsDialog(const bool firstTime)
{
  try {
    FileManager::GetInstance()->Load(&request, firstTime ? "REQ_OPT0.DAT" : "REQ_OPT1.DAT");
    FileManager::GetInstance()->Load(&palette, "OPTIONS.PAL");
    FileManager::GetInstance()->Load(&screen, firstTime ? "OPTIONS0.SCX" : "OPTIONS1.SCX");
    FileManager::GetInstance()->Load(&font, "GAME.FNT");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new OptionsDialog(palette.GetPalette(), new DialogWindow(panel));
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_TEXTBUTTON:
          if (data.visible) {
            panel->AddActiveWidget(widgetFactory.CreateTextButton(data, font, dialog));
          }
          break;
        default:
          break;
      }
    }
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateOptionsDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreatePreferencesDialog()
{
  try {
    FileManager::GetInstance()->Load(&request, "REQ_PREF.DAT");
    FileManager::GetInstance()->Load(&palette, "OPTIONS.PAL");
    FileManager::GetInstance()->Load(&screen, "OPTIONS2.SCX");
    FileManager::GetInstance()->Load(&font, "GAME.FNT");
    FileManager::GetInstance()->Load(&label, "LBL_PREF.DAT");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new OptionsDialog(palette.GetPalette(), new DialogWindow(panel));
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_TEXTBUTTON:
          if (data.visible) {
            panel->AddActiveWidget(widgetFactory.CreateTextButton(data, font, dialog));
          }
          break;
        default:
          break;
      }
    }
    for (unsigned int i = 0; i < label.GetSize(); i++) {
      LabelData data = label.GetLabelData(i);
      panel->AddWidget(widgetFactory.CreateLabel(data, font, request.GetWidth() > screen.GetImage()->GetWidth() ? request.GetWidth() : screen.GetImage()->GetWidth()));
    }
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreatePreferencesDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreateSaveDialog()
{
  try {
    FileManager::GetInstance()->Load(&request, "REQ_SAVE.DAT");
    FileManager::GetInstance()->Load(&palette, "OPTIONS.PAL");
    FileManager::GetInstance()->Load(&screen, "OPTIONS2.SCX");
    FileManager::GetInstance()->Load(&font, "GAME.FNT");
    FileManager::GetInstance()->Load(&label, "LBL_SAVE.DAT");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new OptionsDialog(palette.GetPalette(), new DialogWindow(panel));
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_TEXTBUTTON:
          if (data.visible) {
            panel->AddActiveWidget(widgetFactory.CreateTextButton(data, font, dialog));
          }
          break;
        default:
          break;
      }
    }
    for (unsigned int i = 0; i < label.GetSize(); i++) {
      LabelData data = label.GetLabelData(i);
      panel->AddWidget(widgetFactory.CreateLabel(data, font, request.GetWidth() > screen.GetImage()->GetWidth() ? request.GetWidth() : screen.GetImage()->GetWidth()));
    }
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateSaveDialog");
    throw;
  }
}

Dialog *
DialogFactory::CreateWorldDialog()
{
  try {
    std::stringstream name;
    name << "Z" << std::setw(2) << std::setfill('0') << GameApplication::GetInstance()->GetGame()->GetChapter()->Get() << ".PAL";
    FileManager::GetInstance()->Load(&request, "REQ_MAIN.DAT");
    FileManager::GetInstance()->Load(&palette, name.str());
    FileManager::GetInstance()->Load(&screen, "FRAME.SCX");
    FileManager::GetInstance()->Load(&normal, "BICONS1.BMX");
    FileManager::GetInstance()->Load(&pressed, "BICONS2.BMX");
    FileManager::GetInstance()->Load(&heads, "HEADS.BMX");
    FileManager::GetInstance()->Load(&compass, "COMPASS.BMX");

    PanelWidget *panel = widgetFactory.CreatePanel(request.GetXPos(), request.GetYPos(), request.GetWidth(), request.GetHeight(), screen.GetImage());
    Dialog *dialog = new GameDialog(palette.GetPalette(), new DialogWindow(panel));
    unsigned int nextMember = 0;
    for (unsigned int i = 0; i < request.GetSize(); i++) {
      RequestData data = request.GetRequestData(i);
      switch (data.widget) {
        case REQ_USERDEFINED:
          if ((data.action >= 0) && (data.group == GROUP2)) {
            panel->AddActiveWidget(widgetFactory.CreateCharacterButton(data, GameApplication::GetInstance()->GetGame()->GetParty()->GetActiveMember(nextMember), heads, dialog));
            nextMember++;
          }
          if ((data.action >= 0) && (data.group == GROUP3)) {
            panel->AddWidget(widgetFactory.CreateWorldView(data, GameApplication::GetInstance()->GetGame()));
          }
          break;
        case REQ_IMAGEBUTTON:
          if (data.visible) {
            data.xpos += request.GetXOff();
            data.ypos += request.GetYOff();
            panel->AddActiveWidget(widgetFactory.CreateImageButton(data, normal, pressed, dialog));
          }
          break;
        default:
          break;
      }
    }
    panel->AddWidget(widgetFactory.CreateCompass(GameApplication::GetInstance()->GetGame()->GetCamera(), compass.GetImage(0)));
    return dialog;
  } catch (Exception &e) {
    e.Print("DialogFactory::CreateWorldDialog");
    throw;
  }
}
