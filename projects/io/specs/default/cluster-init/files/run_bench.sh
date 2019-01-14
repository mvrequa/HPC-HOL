#!/bin/bash
#BSUB -J ior-8
#BSUB -n 8
#BSUB -e ~/error.%J
#BSUB -o ~/output.%J
SOFTWARE_DIR=/shared/scratch
export PATH=${SOFTWARE_DIR}/mpich3/bin:$PATH
export LD_LIBRARY_PATH=${SOFTWARE_DIR}/mpich3/lib:${LD_LIBRARY_PATH}

DATE_STAMP=`date +"%Y-%m-%d_%H-%M-%S"`
WORK_DIR=/mnt/beegfs/benchmarks/test_${DATE_STAMP}
mkdir -p $WORK_DIR
mpirun -np 8 -rmk lsf $SOFTWARE_DIR/ior/bin/ior -a MPIIO -v -z -F –w -t 4k -b 1G -o $WORK_DIR

# high throughput
# ior -a MPIIO -v -B -F -w -t 32m -b 4G -o /mnt/glusterfs/benchmarks/test_${DATE_STAMP}

# high iops
# ior -w -r -B -C -i4 -t4k -b320m -F -o /mnt/glusterfs/benchmarks/test_${DATE_STAMP} 


