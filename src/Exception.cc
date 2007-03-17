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

#include <iostream>
#include <sstream>

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

Exception::Exception(const std::string &file, const unsigned int line, const std::string &msg)
: filename(file)
, linenr(line)
, message(msg) {
}

Exception::Exception(const std::string &file, const unsigned int line, const std::string &msg, const unsigned int val)
: filename(file)
, linenr(line) {
  std::stringstream s;
  s << msg << " (" << val << ")";
  message = s.str();
}

Exception::~Exception() throw() {
}

void
Exception::Print(const std::string &handler) const throw() {
  std::cerr << handler << " >> " << filename << ":" << linenr << " " << message << std::endl;
}

std::string
Exception::What() const throw() {
  std::stringstream s;
  s << filename << ":" << linenr << " " << message;
  return s.str();
}

BufferEmpty::BufferEmpty(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, BUFFER_EMPTY + " " + msg) {
}

BufferEmpty::~BufferEmpty() throw() {
}

BufferFull::BufferFull(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, BUFFER_FULL + " " + msg) {
}

BufferFull::~BufferFull() throw() {
}

CompressionError::CompressionError(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, COMPRESSION_ERROR + " " + msg) {
}

CompressionError::~CompressionError() throw() {
}

DataCorruption::DataCorruption(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, DATA_CORRUPTION + " " + msg) {
}

DataCorruption::~DataCorruption() throw() {
}

FileNotFound::FileNotFound(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, FILE_NOT_FOUND + " (" + msg + ")") {
}

FileNotFound::~FileNotFound() throw() {
}

IndexOutOfRange::IndexOutOfRange(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, INDEX_OUT_OF_RANGE + " " + msg) {
}

IndexOutOfRange::~IndexOutOfRange() throw() {
}

IOError::IOError(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, IO_ERROR + " " + msg) {
}

IOError::~IOError() throw() {
}

NullPointer::NullPointer(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, NULL_POINTER + " " + msg) {
}

NullPointer::~NullPointer() throw() {
}

OpenError::OpenError(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, OPEN_ERROR + " " + msg) {
}

OpenError::~OpenError() throw() {
}

SDL_Exception::SDL_Exception(const std::string &file, const unsigned int line, const std::string &msg)
: Exception(file, line, SDL_EXCEPTION + " " + msg) {
}

SDL_Exception::~SDL_Exception() throw() {
}

UnexpectedValue::UnexpectedValue(const std::string &file, const unsigned int line, const std::string &value)
: Exception(file, line, UNEXPECTED_VALUE + " " + value) {
}

UnexpectedValue::UnexpectedValue(const std::string &file, const unsigned int line, const unsigned int value)
: Exception(file, line, UNEXPECTED_VALUE, value) {
}

UnexpectedValue::~UnexpectedValue() throw() {
}
