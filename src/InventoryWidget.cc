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
#include "InventoryWidget.h"
#include "ObjectResource.h"
#include "WidgetFactory.h"

static const int MAX_INVENTOY_WIDGET_WIDTH  = 80;
static const int MAX_INVENTOY_WIDGET_HEIGHT = 58;

InventoryWidget::InventoryWidget(const Rectangle &r, const Inventory *inv, ImageResource& img, Font *f)
: ContainerWidget(r)
, Observer()
, inventory(inv)
, images(img)
, font(f)
, freeSpaces()
{
  Update();
}

InventoryWidget::~InventoryWidget()
{
}

void
InventoryWidget::Update()
{
  Clear();
  WidgetFactory wf;
  freeSpaces.push_back(rect);
  for (unsigned int i = 0; i < inventory->GetSize(); i++) {
    InventoryItem *item = inventory->GetItem(i);
    if (!(item->IsEquiped())) {
      Image *image = images.GetImage(item->GetId());
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
          InventoryItemWidget *invitem = wf.CreateInventoryItem(Rectangle(it->GetXPos() + 1, it->GetYPos() + 1, width, height),
                                                                INVENTORY_OFFSET + i, image, item->ToString(), font);
          AddActiveWidget(invitem);
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
}
