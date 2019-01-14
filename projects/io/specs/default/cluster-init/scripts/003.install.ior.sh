#!/bin/bash
SOFTWARE_DIR=$(jetpack config io.install_dir)
export PATH=${SOFTWARE_DIR}/mpich3/bin:$PATH
export LD_LIBRARY_PATH=${SOFTWARE_DIR}/mpich3/lib:${LD_LIBRARY_PATH}

cd $SOFTWARE_DIR/
yum -y install git automake
#git clone https://github.com/chaos/ior.git
#mv ior ior_src
#cd ior_src/
#./bootstrap
#./configure --prefix=$SOFTWARE_DIR/ior/
#make
#make install


git clone https://github.com/hpc/ior
cd ior/
./bootstrap 
./configure --prefix=/$SOFTWARE_DIR/ior
make
make install
