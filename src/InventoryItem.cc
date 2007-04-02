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

static const unsigned int REPAIRABLE_MASK = 0x0020;
static const unsigned int EQUIPED_MASK    = 0x0040;

InventoryItem::InventoryItem(const unsigned int i, const unsigned int v, const unsigned int f)
: id(i)
, value(v)
, flags(f)
{
}

InventoryItem::InventoryItem(const InventoryItem &item)
: id(item.id)
, value(item.value)
, flags(item.flags)
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
InventoryItem::GetValue() const
{
  return value;
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
InventoryItem::Equip(const bool toggle)
{
  if (toggle) {
    flags |= EQUIPED_MASK;
  } else {
    flags &= ~EQUIPED_MASK;
  }
}

InventoryItem &
InventoryItem::operator=(const InventoryItem &item)
{
  id = item.id;
  value = item.value;
  flags = item.flags;
  return *this;
}


SingleInventoryItem::SingleInventoryItem(const unsigned int i)
: InventoryItem(i, 0, 0)
{
}

SingleInventoryItem::~SingleInventoryItem()
{
}

bool
SingleInventoryItem::operator==(const SingleInventoryItem &) const
{
  return false;
}

bool
SingleInventoryItem::operator!=(const SingleInventoryItem &) const
{
  return true;
}


MultipleInventoryItem::MultipleInventoryItem(const unsigned int i, const unsigned int n)
: InventoryItem(i, n, 0)
{
}

MultipleInventoryItem::~MultipleInventoryItem()
{
}

void
MultipleInventoryItem::Add(const unsigned int n)
{
  value += n;
}

void
MultipleInventoryItem::Remove(const unsigned int n)
{
  value -= n;
}

bool
MultipleInventoryItem::operator==(const MultipleInventoryItem &item) const
{
  return (id == item.id);
}

bool
MultipleInventoryItem::operator!=(const MultipleInventoryItem &item) const
{
  return (id != item.id);
}


RepairableInventoryItem::RepairableInventoryItem(const unsigned int i, const unsigned int c)
: InventoryItem(i, c, REPAIRABLE_MASK)
{
}

RepairableInventoryItem::~RepairableInventoryItem()
{
}

void
RepairableInventoryItem::Repair(const unsigned int n)
{
  value += n;
}

void
RepairableInventoryItem::Damage(const unsigned int n)
{
  value -= n;
}

bool
RepairableInventoryItem::operator==(const RepairableInventoryItem &) const
{
  return false;
}

bool
RepairableInventoryItem::operator!=(const RepairableInventoryItem &) const
{
  return true;
}


UsableInventoryItem::UsableInventoryItem(const unsigned int i, const unsigned int u)
: InventoryItem(i, u, 0)
{
}

UsableInventoryItem::~UsableInventoryItem()
{
}

void
UsableInventoryItem::Use(const unsigned int n)
{
  value += n;
}

void
UsableInventoryItem::Restore(const unsigned int n)
{
  value -= n;
}

bool
UsableInventoryItem::operator==(const UsableInventoryItem &) const
{
  return false;
}

bool
UsableInventoryItem::operator!=(const UsableInventoryItem &) const
{
  return true;
}
