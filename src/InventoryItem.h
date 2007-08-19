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

#ifndef INVENTORY_ITEM_H
#define INVENTORY_ITEM_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <string>

static const unsigned int REPAIRABLE_MASK = 0x0020;
static const unsigned int EQUIPED_MASK    = 0x0040;

class InventoryItem
{
protected:
    unsigned int id;
    unsigned int value;
    unsigned int flags;
public:
    InventoryItem ( const unsigned int i, const unsigned int v, const unsigned int f );
    InventoryItem ( const InventoryItem &item );
    virtual ~InventoryItem();
    unsigned int GetId() const;
    unsigned int GetValue() const;
    unsigned int GetFlags() const;
    bool IsEquiped() const;
    void Equip ( const bool toggle );
    virtual const std::string ToString() const = 0;
    InventoryItem& operator= ( const InventoryItem &item );
};

class SingleInventoryItem
            : public InventoryItem
{
public:
    SingleInventoryItem ( const unsigned int i );
    virtual ~SingleInventoryItem();
    const std::string ToString() const;
    bool operator== ( const SingleInventoryItem &item ) const;
    bool operator!= ( const SingleInventoryItem &item ) const;
};

class MultipleInventoryItem
            : public InventoryItem
{
public:
    MultipleInventoryItem ( const unsigned int i, const unsigned int n );
    virtual ~MultipleInventoryItem();
    unsigned int GetAmount() const;
    void Add ( const unsigned int n );
    void Remove ( const unsigned int n );
    const std::string ToString() const;
    bool operator== ( const MultipleInventoryItem &item ) const;
    bool operator!= ( const MultipleInventoryItem &item ) const;
};

class RepairableInventoryItem
            : public InventoryItem
{
public:
    RepairableInventoryItem ( const unsigned int i, const unsigned int c );
    virtual ~RepairableInventoryItem();
    unsigned int GetCondition() const;
    void Repair ( const unsigned int n );
    void Damage ( const unsigned int n );
    const std::string ToString() const;
    bool operator== ( const RepairableInventoryItem &item ) const;
    bool operator!= ( const RepairableInventoryItem &item ) const;
};

class UsableInventoryItem
            : public InventoryItem
{
public:
    UsableInventoryItem ( const unsigned int i, const unsigned int u );
    virtual ~UsableInventoryItem();
    unsigned int GetUses() const;
    void Use ( const unsigned int n );
    void Restore ( const unsigned int n );
    const std::string ToString() const;
    bool operator== ( const UsableInventoryItem &item ) const;
    bool operator!= ( const UsableInventoryItem &item ) const;
};

#endif
