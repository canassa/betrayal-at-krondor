# Process this file with autoconf to produce a configure script.
AC_PREREQ(2.59)
AC_INIT(xbak, 0.0.13, guidoj@users.sf.net)
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
SDL_VERSION=1.2.8
AM_PATH_SDL($SDL_VERSION,,AC_MSG_ERROR([SDL $SDL_VERSION not found!]))
AC_CHECK_LIB([SDL_mixer],[Mix_Linked_Version])
AC_CHECK_LIB([SDL_sound],[Sound_GetLinkedVersion])
SDL_LIBS=$(sh sdl-config --libs)
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
CPPFLAGS="$CPPFLAGS -DDATADIR='\"$datadir\"'"
SDL_CFLAGS=$(sh sdl-config --cflags)
CXXFLAGS="$CXXFLAGS $SDL_CFLAGS -Wall -Werror -Wpointer-arith -Wcast-qual -Wwrite-strings -Wshadow -Wcast-align -Winline -ansi -pedantic"

AC_C_CONST
AC_FUNC_STAT
AC_HEADER_STDC
AC_HEADER_STDBOOL
AC_TYPE_SIZE_T

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
AC_CHECK_FUNCS([atan])
AC_CHECK_FUNCS([cos])
AC_CHECK_FUNCS([sin])

AC_CACHE_SAVE

AC_CONFIG_FILES([Makefile
                 src/Makefile])
AC_OUTPUT
