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

ImageButtonWidget*
WidgetFactory::CreateImageButton(RequestData& data, ActionEventListener *ael)
{
  ImageButtonWidget *button = new ImageButtonWidget(data.xpos, data.ypos, data.width, data.height, data.action);
  button->SetImage(0, 0, 0);
  button->AddActionListener(ael);
  return button;
}

TextButtonWidget*
WidgetFactory::CreateTextButton(RequestData& data, FontResource *fnt, ActionEventListener *ael)
{
  TextButtonWidget *button = new TextButtonWidget(data.xpos, data.ypos, data.width, data.height, data.action);
  button->SetLabel(data.label, fnt);
  button->AddActionListener(ael);
  return button;
}

ChoiceWidget*
WidgetFactory::CreateChoice()
{
  return 0;
}

LabelWidget*
WidgetFactory::CreateLabel(LabelData& data, FontResource *fnt, const int panelWidth)
{
  unsigned int width = 1;
  switch (data.type) {
    case LBL_STANDARD:
      for (unsigned int i = 0; i < data.label.length(); i++) {
        width += fnt->GetWidth((unsigned int)data.label[i] - fnt->GetFirst());
      }
      break;
    case LBL_TITLE:
      width = panelWidth;
      break;
    default:
      break;
  }
  LabelWidget *label = new LabelWidget(data.xpos, data.ypos, width, fnt->GetHeight() + 1, fnt);
  label->SetText(data.label);
  label->SetColor(data.color);
  if (data.type == LBL_TITLE) {
    label->SetShadow(data.shadow);
    label->SetAlignment(HA_CENTER, VA_TOP);
  }
  return label;
}

PanelWidget*
WidgetFactory::CreatePanel(RequestResource *req, ScreenResource *scr, LabelResource *lbl, FontResource *fnt, ActionEventListener *ael)
{
  PanelWidget *panel = new PanelWidget(req->GetXPos(), req->GetYPos(), req->GetWidth(), req->GetHeight());
  panel->SetBackground(scr->GetImage());
  for (unsigned int i = 0; i < req->GetSize(); i++) {
    RequestData data = req->GetRequestData(i);
    data.xpos += req->GetXOff();
    data.ypos += req->GetYOff();
    switch (data.widget) {
      case REQ_USERDEFINED:
        break;
      case REQ_TEXTBUTTON:
        if (data.visible) {
          TextButtonWidget *button = CreateTextButton(data, fnt, ael);
          panel->AddActiveWidget(button);
        }
        break;
      case REQ_IMAGEBUTTON:
        if (data.visible) {
          ImageButtonWidget *button = CreateImageButton(data, ael);
          panel->AddActiveWidget(button);
        }
        break;
      case REQ_SELECT:
        break;
      default:
        break;
    }
  }
  if (lbl) {
    for (unsigned int i = 0; i < lbl->GetSize(); i++) {
      LabelData data = lbl->GetLabelData(i);
      int panelWidth = (req->GetWidth() > scr->GetImage()->GetWidth() ? req->GetWidth() : scr->GetImage()->GetWidth());
      LabelWidget *label = CreateLabel(data, fnt, panelWidth);
      panel->AddWidget(label);
    }
  }
  return panel;
}

TickboxWidget*
WidgetFactory::CreateTickbox()
{
  return 0;
}
