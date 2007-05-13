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

Inventory::Inventory()
: items()
{
}

Inventory::~Inventory()
{
  for (std::list<InventoryItem *>::iterator it = items.begin(); it != items.end(); ++it) {
    delete (*it);
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
  std::list<InventoryItem *>::iterator it = items.begin();
  for (unsigned int i =0; i < n;i++) ++it;
  return *it;
}

std::list<InventoryItem *>::iterator
Inventory::Find(SingleInventoryItem* item)
{
  std::list<InventoryItem *>::iterator it = items.begin();
  while (it != items.end()) {
    SingleInventoryItem *sii = dynamic_cast<SingleInventoryItem *>(*it);
    if (sii && (*sii == *item)) {
      break;
    }
    ++it;
  }
  return it;
}

std::list<InventoryItem *>::iterator
Inventory::Find(MultipleInventoryItem* item)
{
  std::list<InventoryItem *>::iterator it = items.begin();
  while (it != items.end()) {
    MultipleInventoryItem *mii = dynamic_cast<MultipleInventoryItem *>(*it);
    if (mii && (*mii == *item)) {
      break;
    }
    ++it;
  }
  return it;
}

std::list<InventoryItem *>::iterator
Inventory::Find(RepairableInventoryItem* item)
{
  std::list<InventoryItem *>::iterator it = items.begin();
  while (it != items.end()) {
    RepairableInventoryItem *rii = dynamic_cast<RepairableInventoryItem *>(*it);
    if (rii && (*rii == *item)) {
      break;
    }
    ++it;
  }
  return it;
}

std::list<InventoryItem *>::iterator
Inventory::Find(UsableInventoryItem* item)
{
  std::list<InventoryItem *>::iterator it = items.begin();
  while (it != items.end()) {
    UsableInventoryItem *uii = dynamic_cast<UsableInventoryItem *>(*it);
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
  items.push_back(item);
}

void
Inventory::Remove(SingleInventoryItem* item)
{
  items.remove(item);
}

void
Inventory::Add(MultipleInventoryItem* item)
{
  std::list<InventoryItem *>::iterator it = Find(item);
  if (it != items.end()) {
    MultipleInventoryItem *mii = dynamic_cast<MultipleInventoryItem *>(*it);
    mii->Add(item->GetValue());
  } else {
    items.push_back(item);
  }
}

void
Inventory::Remove(MultipleInventoryItem* item)
{
  std::list<InventoryItem *>::iterator it = Find(item);
  if (it != items.end()) {
    MultipleInventoryItem *mii = dynamic_cast<MultipleInventoryItem *>(*it);
    mii->Remove(item->GetValue());
    if (mii->GetValue() == 0) {
      items.remove(item);
    }
  } else {
    throw UnexpectedValue(__FILE__, __LINE__, "items.end()");
  }
}

void
Inventory::Add(RepairableInventoryItem* item)
{
  items.push_back(item);
}

void
Inventory::Remove(RepairableInventoryItem* item)
{
  items.remove(item);
}

void
Inventory::Add(UsableInventoryItem* item)
{
  items.push_back(item);
}

void
Inventory::Remove(UsableInventoryItem* item)
{
  items.remove(item);
}
