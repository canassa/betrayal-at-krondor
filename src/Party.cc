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

#include "Party.h"

Party::Party()
: members()
{
}

Party::~Party()
{
  for (unsigned int i = 0; i < members.size(); i++) {
    delete members[i];
  }
  members.clear();
}

PlayerCharacter *
Party::GetMember(const unsigned int n)
{
  return members[n];
}

PlayerCharacter *
Party::GetActiveMember(const int order)
{
  unsigned int i = 0;
  while (i < members.size()) {
    if (order == members[i]->GetOrder()) {
      return members[i];
    }
    i++;
  }
  return 0;
}

PlayerCharacter *
Party::GetSelectedMember()
{
  unsigned int i = 0;
  while (i < members.size()) {
    if (members[i]->IsSelected()) {
      return members[i];
    }
    i++;
  }
  return 0;
}

void
Party::AddMember(PlayerCharacter *pc)
{
  members.push_back(pc);
}

void
Party::ActivateMember(const unsigned int n, const int order)
{
  PlayerCharacter *pc = GetActiveMember(order);
  if (pc) {
    pc->SetOrder(-1);
  }
  members[n]->SetOrder(order);
}

void
Party::SelectMember(const int order)
{
  for (unsigned int i = 0; i < members.size(); i++) {
    members[i]->Select((order >= 0) && (members[i]->GetOrder() == order));
  }
}
