#!/bin/bash
set -e

# source: https://www.if-not-true-then-false.com/2023/fedora-build-gcc/
cd


sudo dnf group install development-tools

sudo dnf install mpfr-devel gmp-devel libmpc-devel \
zlib-devel glibc-devel.i686 glibc-devel isl-devel \
g++ gcc-gnat gcc-gdc libgphobos-static

wget https://ftp.gwdg.de/pub/misc/gcc/releases/gcc-13.4.0/gcc-13.4.0.tar.xz \
https://ftp.gwdg.de/pub/misc/gcc/releases/gcc-13.4.0/gcc-13.4.0.tar.xz.sig

tar xvf gcc-13.4.0.tar.xz
cd gcc-13.4.0
mkdir build
cd build

../configure --enable-bootstrap \
--enable-languages=c,c++,fortran,objc,obj-c++,ada,go,d,lto \
--prefix=/usr --program-suffix=-13.4 --mandir=/usr/share/man \
--infodir=/usr/share/info --enable-shared --enable-threads=posix \
--enable-checking=release --enable-multilib --with-system-zlib \
--enable-__cxa_atexit --disable-libunwind-exceptions \
--enable-gnu-unique-object --enable-linker-build-id \
--with-gcc-major-version-only --enable-libstdcxx-backtrace \
--with-libstdcxx-zoneinfo=/usr/share/zoneinfo --with-linker-hash-style=gnu \
--enable-plugin --enable-initfini-array --with-isl \
--enable-offload-targets=nvptx-none --enable-offload-defaulted \
--enable-gnu-indirect-function --enable-cet --with-tune=generic \
--with-arch_32=i686 --build=x86_64-redhat-linux \
--with-build-config=bootstrap-lto --enable-link-serialization=1 \
--with-default-libstdcxx-abi=new --with-build-config=bootstrap-lto

make -j"$(nproc)"
sudo make install

gcc-13.4 -v
