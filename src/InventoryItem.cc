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

#include "InventoryItem.h"

static const unsigned int EQUIPED_MASK = 0x0040;

InventoryItem::InventoryItem(const unsigned int i, const unsigned int a, const unsigned int f)
: id(i)
, amount(a)
, flags(f)
{
}

InventoryItem::~InventoryItem()
{
}

unsigned int
InventoryItem::GetId() const
{
  return id;
}

unsigned int
InventoryItem::GetAmount() const
{
  return amount;
}

unsigned int
InventoryItem::GetFlags() const
{
  return flags;
}

bool
InventoryItem::IsEquiped() const
{
  return flags & EQUIPED_MASK;
}

void
InventoryItem::Add(const unsigned int n)
{
  amount += n;
}

void
InventoryItem::Remove(const unsigned int n)
{
  amount -= n;
}

void
InventoryItem::Equip(const bool toggle)
{
  if (toggle) {
    flags |= EQUIPED_MASK;
  } else {
    flags &= ~EQUIPED_MASK;
  }
}
