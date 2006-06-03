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

#include "Exception.h"

static const std::string BUFFER_EMPTY       = "Buffer is empty";
static const std::string BUFFER_FULL        = "Buffer is full";
static const std::string COMPRESSION_ERROR  = "Unknown compression method";
static const std::string DATA_CORRUPTION    = "Data corruption";
static const std::string FILE_NOT_FOUND     = "File not found";
static const std::string INDEX_OUT_OF_RANGE = "Index out of range";
static const std::string IO_ERROR           = "Read/write error";
static const std::string MEMORY_ERROR       = "Out of memory";
static const std::string NULL_POINTER       = "Null pointer";
static const std::string OPEN_ERROR         = "File not open";
static const std::string SDL_EXCEPTION      = "SDL error";
static const std::string UNEXPECTED_VALUE   = "Unexpected value";

Exception::Exception(const std::string &loc, const std::string &msg): location(loc), message(msg) {
}

Exception::~Exception() throw() {
}

void
Exception::Print(const std::string &handler) const throw() {
  std::cerr << handler << " >> " << location << " >> " << message << std::endl;
}

std::string
Exception::What() const throw() {
  return location + " >> " + message;
}

BufferEmpty::BufferEmpty(const std::string &loc):Exception(loc, BUFFER_EMPTY) {
}

BufferEmpty::~BufferEmpty() throw() {
}

BufferFull::BufferFull(const std::string &loc):Exception(loc, BUFFER_FULL) {
}

BufferFull::~BufferFull() throw() {
}

CompressionError::CompressionError(const std::string &loc):Exception(loc, COMPRESSION_ERROR) {
}

CompressionError::~CompressionError() throw() {
}

DataCorruption::DataCorruption(const std::string &loc):Exception(loc, DATA_CORRUPTION) {
}

DataCorruption::~DataCorruption() throw() {
}

FileNotFound::FileNotFound(const std::string &loc):Exception(loc, FILE_NOT_FOUND) {
}

FileNotFound::~FileNotFound() throw() {
}

IndexOutOfRange::IndexOutOfRange(const std::string &loc):Exception(loc, INDEX_OUT_OF_RANGE) {
}

IndexOutOfRange::~IndexOutOfRange() throw() {
}

IOError::IOError(const std::string &loc):Exception(loc, IO_ERROR) {
}

IOError::~IOError() throw() {
}

NullPointer::NullPointer(const std::string &loc):Exception(loc, NULL_POINTER) {
}

NullPointer::~NullPointer() throw() {
}

OpenError::OpenError(const std::string &loc):Exception(loc, OPEN_ERROR) {
}

OpenError::~OpenError() throw() {
}

SDL_Exception::SDL_Exception(const std::string &loc):Exception(loc, SDL_EXCEPTION) {
}

SDL_Exception::~SDL_Exception() throw() {
}

UnexpectedValue::UnexpectedValue(const std::string &loc):Exception(loc, UNEXPECTED_VALUE) {
}

UnexpectedValue::~UnexpectedValue() throw() {
}

