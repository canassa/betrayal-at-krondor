#
# This file is part of xBaK.
#
# xBaK is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# xBaK is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with xBaK.  If not, see <http://www.gnu.org/licenses/>.
#
# Copyright (C) Guido de Jong <guidoj@users.sf.net>
#

# Process this file with autoconf to produce a configure script.
AC_PREREQ(2.63)
AC_INIT(xbak, 0.1.6-svn, guidoj@users.sf.net)
AC_CONFIG_SRCDIR([config.h.in])
AC_CONFIG_HEADER([config.h])
AC_CANONICAL_TARGET
AM_INIT_AUTOMAKE

# Checks for programs.
AC_PROG_AWK
AC_PROG_CC
AC_PROG_CPP
AC_PROG_CXX
AC_PROG_INSTALL
AC_PROG_LN_S
AC_PROG_MAKE_SET
AC_PROG_RANLIB

AC_CACHE_SAVE

# Checks for libraries.
SDL_VERSION=1.2.13
AM_PATH_SDL($SDL_VERSION,,AC_MSG_ERROR([SDL $SDL_VERSION not found!]))
AC_CHECK_LIB([SDL_mixer],[Mix_Linked_Version])
AC_CHECK_LIB([SDL_sound],[Sound_GetLinkedVersion])
#SDL_LIBS=$(sh sdl-config --libs)
LIBS="$LIBS $SDL_LIBS"

AC_CACHE_SAVE

# Checks for header files.
AC_CHECK_HEADERS([errno.h])
AC_CHECK_HEADERS([math.h])
AC_CHECK_HEADERS([stdint.h])
AC_CHECK_HEADERS([stdlib.h])
AC_CHECK_HEADERS([string.h])
AC_CHECK_HEADERS([unistd.h])

AC_CACHE_SAVE

# Checks for typedefs, structures, and compiler characteristics.
AC_LANG([C++])
OPT_CXXFLAGS=""
AC_ARG_ENABLE([error-on-warning], AS_HELP_STRING([--enable-error-on-warning],[treat compiler warnings as errors (optional)]),OPT_CXXFLAGS="$OPT_CXXFLAGS -Werror")
AC_ARG_ENABLE([debug],AS_HELP_STRING([--enable-debug],[enable debugging support (default is NO)]),CPPFLAGS="$CPPFLAGS -DDEBUG")
CPPFLAGS="$CPPFLAGS -DDATADIR='\"$datadir\"'"
#SDL_CFLAGS=$(sh sdl-config --cflags)
CXXFLAGS="$CXXFLAGS $SDL_CFLAGS -ansi -pedantic -Wall -Wextra -Wpointer-arith -Wcast-qual -Wwrite-strings -Wshadow -Wcast-align $OPT_CXXFLAGS"
LDFLAGS="$LDFLAGS -Wl,--as-needed"

AC_C_CONST
AC_FUNC_STAT
AC_HEADER_STDC
AC_HEADER_STDBOOL
AC_TYPE_SIZE_T
AC_TYPE_INT8_T
AC_TYPE_INT16_T
AC_TYPE_INT32_T
AC_TYPE_UINT8_T
AC_TYPE_UINT16_T
AC_TYPE_UINT32_T

AC_CHECK_SIZEOF([char])
AC_CHECK_SIZEOF([short])
AC_CHECK_SIZEOF([int])
AC_CHECK_SIZEOF([long])
AC_CHECK_SIZEOF([long long])
AC_CHECK_SIZEOF([void*])

AC_CACHE_SAVE

# Checks for library functions.
AC_CHECK_FUNCS([getenv])
AC_CHECK_FUNCS([memcpy])
AC_CHECK_FUNCS([memset])
AC_CHECK_FUNCS([mkdir])
AC_CHECK_FUNCS([stat])
AC_CHECK_FUNCS([strncmp])
AC_CHECK_FUNCS([strncpy])
AC_CHECK_FUNCS([abs])
AC_CHECK_FUNCS([atan])
AC_CHECK_FUNCS([cos])
AC_CHECK_FUNCS([sin])
AC_CHECK_FUNCS([sqrt])

AC_CACHE_SAVE

AC_CONFIG_FILES([Makefile
                 src/Makefile])
AC_OUTPUT
