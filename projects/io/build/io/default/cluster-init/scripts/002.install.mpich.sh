#!/bin/bash
set -x
SOFTWARE_DIR=$(jetpack config io.install_dir)
yum -y install gcc gcc-gfortran gcc-c++
mkdir $SOFTWARE_DIR
cd  $SOFTWARE_DIR/

if [ ! -f mpich-3.1.4.tar.gz ]; then
  wget http://www.mpich.org/static/downloads/3.1.4/mpich-3.1.4.tar.gz
fi
tar xzf mpich-3.1.4.tar.gz
cd mpich-3.1.4
./configure --prefix=$SOFTWARE_DIR/mpich3/
make
make install 

