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

#include "WidgetFactory.h"

WidgetFactory::WidgetFactory()
{
}

WidgetFactory::~WidgetFactory()
{
}

ButtonWidget*
WidgetFactory::CreateButton(RequestData& data, FontResource &fnt, WidgetCallBack *wcb)
{
  ButtonWidget *button = new ButtonWidget(data.xpos, data.ypos, data.width, data.height);
  button->SetLabel(data.label, &fnt);
  button->SetAction(data.action);
  button->SetCallBack(wcb);
  return button;
}

ChoiceWidget*
WidgetFactory::CreateChoice()
{
  return 0;
}

PanelWidget*
WidgetFactory::CreatePanel(RequestResource &req, ScreenResource &scr, FontResource &fnt, WidgetCallBack *wcb)
{
  PanelWidget *panel = new PanelWidget(req.GetXPos(), req.GetYPos(), req.GetWidth(), req.GetHeight());
  panel->SetBackground(scr.GetImage());
  for (unsigned int i = 0; i < req.GetSize(); i++) {
    RequestData data = req.GetRequestData(i);
    data.xpos += req.GetXOff();
    data.ypos += req.GetYOff();
    switch (data.widget) {
      case REQ_BUTTON:
        if (data.visible) {
          ButtonWidget *button = CreateButton(data, fnt, wcb);
          panel->AddWidget(button);
        }
        break;
      case REQ_SELECT:
        break;
      default:
        break;
    }
  }
  return panel;
}

TickboxWidget*
WidgetFactory::CreateTickbox()
{
  return 0;
}
