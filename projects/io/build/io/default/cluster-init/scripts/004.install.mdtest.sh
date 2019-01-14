#!/bin/bash
exit 0
SOFTWARE_DIR=$(jetpack config io.install_dir)
cd $SOFTWARE_DIR/
https://github.com/hpc/ior.git
https://github.com/IOR-LANL/ior
git clone https://github.com/MDTEST-LANL/mdtest.git
cd mdtest
export MPI_CC=mpicc
make
