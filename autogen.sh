#!/bin/sh
echo "Running aclocal"
aclocal
echo "Running autoheader"
autoheader
echo "Running automake"
automake --add-missing --copy
echo "Running autoconf"
autoconf
echo "Now you are ready to run './configure'"
