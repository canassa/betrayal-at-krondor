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
#include "Inventory.h"
#include "ObjectResource.h"

Inventory::Inventory()
: items()
{
}

Inventory::~Inventory()
{
  for (std::list<InventoryData>::iterator it = items.begin(); it != items.end(); ++it) {
    delete it->item;
  }
  items.clear();
}

unsigned int
Inventory::GetSize() const
{
  return items.size();
}

InventoryItem *
Inventory::GetItem(const unsigned int n)
{
  std::list<InventoryData>::iterator it = items.begin();
  for (unsigned int i =0; i < n; i++) ++it;
  return it->item;
}

std::list<InventoryData>::iterator
Inventory::Find(SingleInventoryItem* item)
{
  std::list<InventoryData>::iterator it = items.begin();
  while (it != items.end()) {
    SingleInventoryItem *sii = dynamic_cast<SingleInventoryItem *>(it->item);
    if (sii && (*sii == *item)) {
      break;
    }
    ++it;
  }
  return it;
}

std::list<InventoryData>::iterator
Inventory::Find(MultipleInventoryItem* item)
{
  std::list<InventoryData>::iterator it = items.begin();
  while (it != items.end()) {
    MultipleInventoryItem *mii = dynamic_cast<MultipleInventoryItem *>(it->item);
    if (mii && (*mii == *item)) {
      break;
    }
    ++it;
  }
  return it;
}

std::list<InventoryData>::iterator
Inventory::Find(RepairableInventoryItem* item)
{
  std::list<InventoryData>::iterator it = items.begin();
  while (it != items.end()) {
    RepairableInventoryItem *rii = dynamic_cast<RepairableInventoryItem *>(it->item);
    if (rii && (*rii == *item)) {
      break;
    }
    ++it;
  }
  return it;
}

std::list<InventoryData>::iterator
Inventory::Find(UsableInventoryItem* item)
{
  std::list<InventoryData>::iterator it = items.begin();
  while (it != items.end()) {
    UsableInventoryItem *uii = dynamic_cast<UsableInventoryItem *>(it->item);
    if (uii && (*uii == *item)) {
      break;
    }
    ++it;
  }
  return it;
}

void
Inventory::Add(SingleInventoryItem* item)
{
  items.push_back(InventoryData(ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize, item));
  items.sort();
}

void
Inventory::Remove(SingleInventoryItem* item)
{
  items.remove(InventoryData(ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize, item));
}

void
Inventory::Add(MultipleInventoryItem* item)
{
  std::list<InventoryData>::iterator it = Find(item);
  if (it != items.end()) {
    MultipleInventoryItem *mii = dynamic_cast<MultipleInventoryItem *>(it->item);
    mii->Add(item->GetValue());
  } else {
    items.push_back(InventoryData(ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize, item));
    items.sort();
  }
}

void
Inventory::Remove(MultipleInventoryItem* item)
{
  std::list<InventoryData>::iterator it = Find(item);
  if (it != items.end()) {
    MultipleInventoryItem *mii = dynamic_cast<MultipleInventoryItem *>(it->item);
    mii->Remove(item->GetValue());
    if (mii->GetValue() == 0) {
      items.remove(InventoryData(ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize, item));
    }
  } else {
    throw UnexpectedValue(__FILE__, __LINE__, "items.end()");
  }
}

void
Inventory::Add(RepairableInventoryItem* item)
{
  items.push_back(InventoryData(ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize, item));
  items.sort();
}

void
Inventory::Remove(RepairableInventoryItem* item)
{
  items.remove(InventoryData(ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize, item));
}

void
Inventory::Add(UsableInventoryItem* item)
{
  items.push_back(InventoryData(ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize, item));
  items.sort();
}

void
Inventory::Remove(UsableInventoryItem* item)
{
  items.remove(InventoryData(ObjectResource::GetInstance()->GetObjectInfo(item->GetId()).imageSize, item));
}
