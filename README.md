1) 	Install singularity on HPC

2)	Build afni.simg from docker hub: 
	singularity build afni.simg docker://afni/afni
	
	Afni seems to keep docker hub updated:
	singularity exec afni.simg afni --version 

3)	If using slurm, use gPPI.sbatch to call gPPI.sbatch.sh
	These should be in subject parent directory. 

4) 	For other schedulers, modify gPPI.sbach.sh

5)	I tested this in 3 segments then merged them into gPPI.sh. 
	Hopefully nothing broke when concatenatating the orginal scripts.
