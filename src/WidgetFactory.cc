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

TextButtonWidget*
WidgetFactory::CreateTextButton(RequestData& data, FontResource *fnt, ActionEventListener *ael)
{
  TextButtonWidget *button = new TextButtonWidget(data.xpos, data.ypos, data.width, data.height, data.action);
  button->SetLabel(data.label, fnt);
  button->AddActionListener(ael);
  return button;
}

ImageButtonWidget*
WidgetFactory::CreateImageButton(RequestData& data, ImageResource *normal, ImageResource *pressed, ActionEventListener *ael)
{
  ImageButtonWidget *button = new ImageButtonWidget(data.xpos, data.ypos, data.width, data.height, data.action);
  Image *normalImage = 0;
  Image *pressedImage = 0;
  if (data.image >= 0) {
    normalImage = normal->GetImage(data.image);
    pressedImage = pressed->GetImage(data.image);
  }
  button->SetImage(normalImage, pressedImage);
  button->AddActionListener(ael);
  return button;
}

CharacterButtonWidget*
WidgetFactory::CreateCharacterButton(RequestData& data, PlayerCharacter *pc, ImageResource *img, ActionEventListener *ael)
{
  CharacterButtonWidget *button = new CharacterButtonWidget(data.xpos, data.ypos, data.width, data.height, data.action);
  button->SetCharacter(pc);
  button->SetImage(img->GetImage(SELECTED_IMAGE));
  button->AddActionListener(ael);
  return button;
}

ChoiceWidget*
WidgetFactory::CreateChoice()
{
  return 0;
}

TickboxWidget*
WidgetFactory::CreateTickbox()
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
WidgetFactory::CreatePanel(WidgetResources& widgetRes)
{
  PanelWidget *panel = new PanelWidget(widgetRes.request->GetXPos(), widgetRes.request->GetYPos(),
                                       widgetRes.request->GetWidth(), widgetRes.request->GetHeight());
  panel->SetBackground(widgetRes.screen->GetImage());
  unsigned int nextMember = 0;
  for (unsigned int i = 0; i < widgetRes.request->GetSize(); i++) {
    RequestData data = widgetRes.request->GetRequestData(i);
    data.xpos += widgetRes.request->GetXOff();
    data.ypos += widgetRes.request->GetYOff();
    switch (data.widget) {
      case REQ_USERDEFINED:
        if ((data.action >= 0) && (data.special == widgetRes.special)) {
          CharacterButtonWidget *button = CreateCharacterButton(data, widgetRes.members[nextMember], widgetRes.heads, widgetRes.eventListener);
          panel->AddActiveWidget(button);
          nextMember++;
        }
        break;
      case REQ_TEXTBUTTON:
        if (data.visible) {
          TextButtonWidget *button = CreateTextButton(data, widgetRes.font, widgetRes.eventListener);
          panel->AddActiveWidget(button);
        }
        break;
      case REQ_IMAGEBUTTON:
        if (data.visible) {
          ImageButtonWidget *button = CreateImageButton(data, widgetRes.normal, widgetRes.pressed, widgetRes.eventListener);
          panel->AddActiveWidget(button);
        }
        break;
      case REQ_SELECT:
        break;
      default:
        break;
    }
  }
  if (widgetRes.label) {
    for (unsigned int i = 0; i < widgetRes.label->GetSize(); i++) {
      LabelData data = widgetRes.label->GetLabelData(i);
      int panelWidth = (widgetRes.request->GetWidth() > widgetRes.screen->GetImage()->GetWidth() ?
                        widgetRes.request->GetWidth() : widgetRes.screen->GetImage()->GetWidth());
      LabelWidget *label = CreateLabel(data, widgetRes.font, panelWidth);
      panel->AddWidget(label);
    }
  }
  return panel;
}
