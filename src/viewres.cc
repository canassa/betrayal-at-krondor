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

#include <iostream>
#include <cstring>

#include "Exception.h"
#include "TestApplication.h"

typedef enum _CommandType
{
  CT_UNKNOWN,
  CT_BMX,
  CT_FNT,
  CT_SCX,
  CT_TTM
} CommandType;

CommandType
get_command_type(char *cmd)
{
  if (!cmd) {
    return CT_UNKNOWN;
  }
  if (strncmp(cmd, "BMX", 3) == 0) {
    return CT_BMX;
  }
  if (strncmp(cmd, "FNT", 3) == 0) {
    return CT_FNT;
  }
  if (strncmp(cmd, "SCX", 3) == 0) {
    return CT_SCX;
  }
  if (strncmp(cmd, "TTM", 3) == 0) {
    return CT_TTM;
  }
  return CT_UNKNOWN;
}

int main(int argc, char **argv)
{
  try {
    TestApplication *app = TestApplication::GetInstance();
    CommandType ct = get_command_type(argv[1]);
    switch (ct) {
      case CT_UNKNOWN:
        printf("Usage: %s <BMX|FNT|SCX|TTM> <command-options>\n", argv[0]);
        return -1;
      case CT_BMX:
        if (argc != 4) {
          printf("Usage: %s BMX <PAL-file> <BMX-file>\n", argv[0]);
          return -1;
        }
        app->ActivatePalette(argv[2]);
        app->ShowImage(argv[3]);
        break;
      case CT_FNT:
        if (argc != 3) {
          printf("Usage: %s FNT <FNT-file>\n", argv[0]);
          return -1;
        }
        app->ActivatePalette();
        app->DrawFont(argv[2]);
        break;
      case CT_SCX:
        if (argc != 4) {
          printf("Usage: %s SCX <PAL-file> <SCX-file>\n", argv[0]);
          return -1;
        }
        app->ActivatePalette(argv[2]);
        app->ShowScreen(argv[3]);
        break;
      case CT_TTM:
        if (argc != 3) {
          printf("Usage: %s TTM <TTM-file>\n", argv[0]);
          return -1;
        }
        app->ActivatePalette();
        app->PlayMovie(argv[2]);
        break;
    }
    TestApplication::CleanUp();
  } catch (Exception &e) {
    e.Print("main");
  } catch (...) {
    /* every exception should have been handled before */
    std::cerr << "Unhandled exception" << std::endl;
  }
  return 0;
}

