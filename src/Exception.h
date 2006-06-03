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

#ifndef EXCEPTION_H
#define EXCEPTION_H

#include <exception>
#include <string>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

class Exception: public std::exception {
  private:
    std::string location;
    std::string message;
  public:
    Exception(const std::string &loc, const std::string &msg);
    virtual ~Exception() throw();
    void Print(const std::string &handler) const throw();
    std::string What() const throw();
};

class BufferEmpty: public Exception {
  public:
    BufferEmpty(const std::string &loc);
    virtual ~BufferEmpty() throw ();
};

class BufferFull: public Exception {
  public:
    BufferFull(const std::string &loc);
    virtual ~BufferFull() throw ();
};

class CompressionError: public Exception {
  public:
    CompressionError(const std::string &loc);
    virtual ~CompressionError() throw ();
};

class DataCorruption: public Exception {
  public:
    DataCorruption(const std::string &loc);
    virtual ~DataCorruption() throw ();
};

class FileNotFound: public Exception {
  public:
    FileNotFound(const std::string &loc);
    virtual ~FileNotFound() throw ();
};

class IndexOutOfRange: public Exception {
  public:
    IndexOutOfRange(const std::string &loc);
    virtual ~IndexOutOfRange() throw ();
};

class IOError: public Exception {
  public:
    IOError(const std::string &loc);
    virtual ~IOError() throw ();
};

class NullPointer: public Exception {
  public:
    NullPointer(const std::string &loc);
    virtual ~NullPointer() throw ();
};

class OpenError: public Exception {
  public:
    OpenError(const std::string &loc);
    virtual ~OpenError() throw ();
};

class SDL_Exception: public Exception {
  public:
    SDL_Exception(const std::string &loc);
    virtual ~SDL_Exception() throw ();
};

class UnexpectedValue: public Exception {
  public:
    UnexpectedValue(const std::string &loc);
    virtual ~UnexpectedValue() throw ();
};

#endif

