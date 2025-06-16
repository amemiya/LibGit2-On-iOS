#!/bin/sh
# From https://gist.github.com/GraemeConradie/49d2f5962fa72952bc6c64ac093db2d5

##
# Install autoconf, automake and libtool smoothly on Mac OS X.
# Newer versions of these libraries are available and may work better on OS X
##

export REPO_ROOT=`pwd`
export build=`pwd`/temp # or wherever you'd like to build
export install=`pwd`/tools
mkdir -p $build

##
# Autoconf
# http://ftpmirror.gnu.org/autoconf

cd $build
curl -OL http://ftpmirror.gnu.org/autoconf/autoconf-2.72.tar.gz
tar xzf autoconf-2.72.tar.gz
cd autoconf-2.72
./configure --prefix=$install
make
make install
# export PATH=$PATH:$install

##
# Automake
# http://ftpmirror.gnu.org/automake

cd $build
curl -OL http://ftpmirror.gnu.org/automake/automake-1.18.tar.gz
tar xzf automake-1.18.tar.gz
cd automake-1.18
./configure --prefix=$install
make
make install

##
# Libtool
# http://ftpmirror.gnu.org/libtool

cd $build
curl -OL http://ftpmirror.gnu.org/libtool/libtool-2.5.4.tar.gz
tar xzf libtool-2.5.4.tar.gz
cd libtool-2.5.4
./configure --prefix=$install
make
make install

echo "Installation complete."

cd $REPO_ROOT
tar -cJf tools.tar.xz tools
