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

#include "Exception.h"
#include "ObjectResource.h"
#include "WidgetFactory.h"

WidgetFactory::WidgetFactory()
{
}

WidgetFactory::~WidgetFactory()
{
}

TextButtonWidget*
WidgetFactory::CreateTextButton(RequestData& data, FontResource &fnt, ActionEventListener *ael)
{
  TextButtonWidget *button = new TextButtonWidget(Rectangle(data.xpos, data.ypos, data.width, data.height), data.action);
  button->SetVisible(data.visible);
  button->SetLabel(data.label, fnt.GetFont());
  button->AddActionListener(ael);
  return button;
}

ImageButtonWidget*
WidgetFactory::CreateImageButton(RequestData& data, ImageResource& normal, ImageResource& pressed, ActionEventListener *ael)
{
  ImageButtonWidget *button = new ImageButtonWidget(Rectangle(data.xpos, data.ypos, data.width, data.height), data.action);
  button->SetVisible(data.visible);
  Image *normalImage = 0;
  Image *pressedImage = 0;
  if (data.image >= 0) {
    normalImage = normal.GetImage(data.image);
    pressedImage = pressed.GetImage(data.image);
  }
  button->SetImage(normalImage, pressedImage);
  button->AddActionListener(ael);
  return button;
}

CharacterButtonWidget*
WidgetFactory::CreateCharacterButton(RequestData& data, PlayerCharacter *pc, ImageResource& img, ActionEventListener *ael)
{
  CharacterButtonWidget *button = new CharacterButtonWidget(Rectangle(data.xpos, data.ypos, data.width, data.height), data.action);
  button->SetCharacter(pc);
  button->SetImage(img.GetImage(SELECTED_IMAGE));
  button->AddActionListener(ael);
  return button;
}

ChoiceWidget*
WidgetFactory::CreateChoice(RequestData& data, ImageResource& img, ActionEventListener *ael)
{
  ChoiceWidget *choice = new ChoiceWidget(Rectangle(data.xpos, data.ypos, data.width, data.height), data.action);
  choice->SetImage(img.GetImage(data.image + 1), img.GetImage(data.image));
  choice->AddActionListener(ael);
  return choice;
}

CompassWidget*
WidgetFactory::CreateCompass(Camera *cam, Image *img)
{
  CompassWidget *compass = new CompassWidget(cam, img);
  return compass;
}

CombatViewWidget*
WidgetFactory::CreateCombatView(RequestData& data, Game *game)
{
  return new CombatViewWidget(Rectangle(data.xpos, data.ypos, data.width, data.height), game);
}

MapViewWidget*
WidgetFactory::CreateMapView(RequestData& data, Game *game)
{
  return new MapViewWidget(Rectangle(data.xpos, data.ypos, data.width, data.height), game);
}

WorldViewWidget*
WidgetFactory::CreateWorldView(RequestData& data, Game *game)
{
  return new WorldViewWidget(Rectangle(data.xpos, data.ypos, data.width, data.height), game);
}

TextWidget*
WidgetFactory::CreateLabel(LabelData& data, FontResource& fnt, const int panelWidth)
{
  unsigned int width = 1;
  switch (data.type) {
    case LBL_STANDARD:
      for (unsigned int i = 0; i < data.label.length(); i++) {
        width += fnt.GetFont()->GetWidth((unsigned int)data.label[i] - fnt.GetFont()->GetFirst());
      }
      break;
    case LBL_TITLE:
      width = panelWidth;
      break;
    default:
      break;
  }
  TextWidget *label = new TextWidget(Rectangle(data.xpos, data.ypos, width, fnt.GetFont()->GetHeight() + 1), fnt.GetFont());
  label->SetText(data.label);
  label->SetColor(data.color);
  if (data.type == LBL_TITLE) {
    label->SetShadow(data.shadow, 0, 1);
    label->SetAlignment(HA_CENTER, VA_TOP);
  }
  return label;
}

BadgeWidget*
WidgetFactory::CreateBadge(const Rectangle &r, const std::string& s, Font *f)
{
  BadgeWidget *badge = new BadgeWidget(r);
  badge->SetLabel(s, f);
  return badge;
}

ImageWidget*
WidgetFactory::CreateImage(const Rectangle &r, Image *img, const Flipping flip)
{
  ImageWidget *image = new ImageWidget(r, img);
  switch (flip) {
    case HORIZONTAL:
      image->HorizontalFlip();
      break;
    case VERTICAL:
      image->VerticalFlip();
      break;
    default:
      break;
  }
  return image;
}

InventoryItemWidget*
WidgetFactory::CreateInventoryItem(const Rectangle &r, Image *img, const int a)
{
  InventoryItemWidget* invitem = new InventoryItemWidget(r, a);
  invitem->SetImage(img);
  return invitem;
}

ContainerWidget *
WidgetFactory::CreateInventory(const Rectangle &r, PlayerCharacter *pc, ImageResource& img)
{
  static const int MAX_INVENTOY_WIDGET_WIDTH  = 80;
  static const int MAX_INVENTOY_WIDGET_HEIGHT = 58;
  ContainerWidget *invwidget = new ContainerWidget(r);
  const Inventory* inv = pc->GetInventory();
  std::list<Rectangle> freeSpaces;
  freeSpaces.push_back(r);
  for (unsigned int i = 0; i < inv->GetSize(); i++) {
    InventoryItem *item = inv->GetItem(i);
    if (!(item->IsEquiped())) {
      Image *image = img.GetImage(item->GetId());
      int width;
      int height;
      switch (ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize) {
        case 1:
          width = MAX_INVENTOY_WIDGET_WIDTH / 2;
          height = MAX_INVENTOY_WIDGET_HEIGHT / 2;
          break;
        case 2:
          width = MAX_INVENTOY_WIDGET_WIDTH;
          height = MAX_INVENTOY_WIDGET_HEIGHT / 2;
          break;
        case 4:
          width = MAX_INVENTOY_WIDGET_WIDTH;
          height = MAX_INVENTOY_WIDGET_HEIGHT;
          break;
        default:
          throw UnexpectedValue(__FILE__, __LINE__, ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize);
          break;
      }
      std::list<Rectangle>::iterator it = freeSpaces.begin();
      while (it != freeSpaces.end()) {
        if ((it->GetWidth() > width) && (it->GetHeight() > height)) {
          Rectangle rect(it->GetXPos() + 1 + (width - image->GetWidth()) / 2,
                         it->GetYPos() + 1 + (height - image->GetHeight()) / 2,
                         image->GetWidth(),
                         image->GetHeight());
          InventoryItemWidget *invitem = CreateInventoryItem(rect, image, INVENTORY_OFFSET + i);
          invwidget->AddActiveWidget(invitem);
          Rectangle origFreeSpace(*it);
          freeSpaces.erase(it);
          if ((origFreeSpace.GetWidth() - width) > (MAX_INVENTOY_WIDGET_WIDTH / 2)) {
            freeSpaces.push_back(Rectangle(origFreeSpace.GetXPos() + width + 1,
                                           origFreeSpace.GetYPos(),
                                           origFreeSpace.GetWidth() - width - 1,
                                           origFreeSpace.GetHeight()));
          }
          if ((origFreeSpace.GetHeight() - height) > (MAX_INVENTOY_WIDGET_HEIGHT / 2)) {
            freeSpaces.push_back(Rectangle(origFreeSpace.GetXPos(),
                                           origFreeSpace.GetYPos() + height + 1,
                                           origFreeSpace.GetWidth(),
                                           origFreeSpace.GetHeight() - height - 1));
          }
          freeSpaces.sort();
        }
        ++it;
      }
    }
  }
  freeSpaces.clear();
  return invwidget;
}

PortraitWidget*
WidgetFactory::CreatePortrait(const Rectangle &r, PlayerCharacter *pc, Image *hb, Image *vb)
{
  PortraitWidget *portrait = new PortraitWidget(r, pc);
  portrait->SetBorders(hb, vb);
  return portrait;
}

RatingsWidget*
WidgetFactory::CreateRatings(const Rectangle &r, PlayerCharacter *pc, Image *hb, Image *vb, Font *f)
{
  RatingsWidget *ratings = new RatingsWidget(r, pc, f);
  ratings->SetBorders(hb, vb);
  return ratings;
}

SkillsWidget*
WidgetFactory::CreateSkills(const Rectangle &r, PlayerCharacter *pc, Image *sw, Image *bl, Font *f)
{
  SkillsWidget *skills = new SkillsWidget(r, pc, sw, bl, f);
  return skills;
}

PanelWidget*
WidgetFactory::CreatePanel(const Rectangle &r, Image *img)
{
  PanelWidget *panel = new PanelWidget(r);
  panel->SetBackground(img);
  return panel;
}
