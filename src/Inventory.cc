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

#include "Inventory.h"

Inventory::Inventory()
: items()
{
}

Inventory::~Inventory()
{
  items.clear();
}

std::list<const InventoryItem *>&
Inventory::GetItems()
{
  return items;
}

std::list<const InventoryItem *>::iterator
Inventory::Find(const InventoryItem* item)
{
  std::list<const InventoryItem *>::iterator it = items.begin();
  while (it != items.end()) {
    if (**it == *item) {
      break;
    }
    ++it;
  }
  return it;
}

void
Inventory::Add(const InventoryItem* item)
{
  std::list<const InventoryItem *>::iterator it = Find(item);
  if (it == items.end()) {
    items.push_back(item);
  } else {
    ((MultipleInventoryItem *)(*it))->Add(item->GetValue());
  }
}

void
Inventory::Remove(const InventoryItem* item)
{
  std::list<const InventoryItem *>::iterator it = Find(item);
  if (it == items.end()) {
    items.remove(item);
  } else {
    ((MultipleInventoryItem *)(*it))->Remove(item->GetValue());
    if ((*it)->GetValue() == 0) {
      items.erase(it);
    }
  }
}
