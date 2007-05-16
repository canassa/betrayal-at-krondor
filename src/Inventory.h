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

#ifndef INVENTORY_H
#define INVENTORY_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <list>

#include "InventoryItem.h"

class Inventory {
  private:
    std::list<InventoryItem *> items;
    std::list<InventoryItem *>::iterator Find(SingleInventoryItem* item);
    std::list<InventoryItem *>::iterator Find(MultipleInventoryItem* item);
    std::list<InventoryItem *>::iterator Find(RepairableInventoryItem* item);
    std::list<InventoryItem *>::iterator Find(UsableInventoryItem* item);
  public:
    Inventory();
    ~Inventory();
    unsigned int GetSize() const;
    InventoryItem* GetItem(const unsigned int n);
    void Add(SingleInventoryItem *item);
    void Remove(SingleInventoryItem *item);
    void Add(MultipleInventoryItem *item);
    void Remove(MultipleInventoryItem *item);
    void Add(RepairableInventoryItem *item);
    void Remove(RepairableInventoryItem *item);
    void Add(UsableInventoryItem *item);
    void Remove(UsableInventoryItem *item);
};

#endif