#!/bin/bash
SOFTWARE_DIR=/tools
export PATH=${SOFTWARE_DIR}/mpich3/bin:$PATH
export LD_LIBRARY_PATH=${SOFTWARE_DIR}/mpich3/lib:${LD_LIBRARY_PATH}
##mpirun -np <n_procs> -<hostfile> ~/nodefile /tools/ior/bin/ior -w -r -B -C -i4 -t4k -b320m -F -o /shared/home/admin/ior 
## /tools/ior/bin/ior -w -r -B -C -i4 -t4k -b320m -F -o /shared/home/admin/ior
## bsub -n 16 -o "/shared/home/admin/%J" /shared/home/admin/run_bench.sh
##mkdir /mnt/glusterfs/benchmarks/$LSB_JOBID
##mpirun -np 32 -rmk lsf /tools/ior/bin/ior -w -r -B -C -i4 -t4k -b320m -F -o /mnt/glusterfs/benchmarks/$LSB_JOBID/$LSB_JOBID


mpirun -np 64 -rmk lsf /tools/ior/bin/ior -a MPIIO -v -z -F –w -t 4k -b 1G -o /mnt/glusterfs/benchmarks/test.`date +"%Y-%m-%d_%H-%M-%S"`

#mpirun -np 64 -rmk lsf /tools/ior/bin/ior -a MPIIO -v -B -F -w -t 32m -b 4G -o /mnt/glusterfs/benchmarks/test.`date +"%Y-%m-%d_%H-%M-%S"`

#mpirun -np 64 -rmk lsf /tools/ior/bin/ior -w -r -B -C -i4 -t4k -b320m -F -o /mnt/glusterfs/benchmarks/test.`date +"%Y-%m-%d_%H-%M-%S"` 


