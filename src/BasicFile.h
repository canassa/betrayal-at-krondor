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

#ifndef GENERIC_FILE_H
#define GENERIC_FILE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "FileBuffer.h"

class BasicFile {
  private:
    std::ifstream ifs;
    std::ofstream ofs;
  public:
    BasicFile();
    virtual ~BasicFile();
    virtual std::string GetDefaultPath() const;
    virtual std::string GetAlternatePath() const;
    virtual std::string GetLastResortPath() const;
    virtual std::string GetStoragePath() const;
    void Open(const std::string &name, const bool writable);
    void Close();
    void Seek(const std::streamoff offset);
    void SeekEnd(const std::streamoff offset);
    std::streamsize Size();
    void Load(FileBuffer &buffer);
    void Save(FileBuffer &buffer);
    void Save(FileBuffer &buffer, const unsigned int n);
};

#endif
