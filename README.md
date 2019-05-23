gPPI using AFNI 

Supports multiple ROIs (one per analyses).
Appropropriate for block and event-related designs.

Generates:
a) Physiological Regressor
b) Interaction Regressor (for each task x physiological interaction)

Follows the generalized form descriped in McLaren et al., 2012:
A generalized form of context-dependent psychophysiological interactions (gPPI): a comparison to standard approaches.


1) 	Install singularity on HPC

2)	Build afni.simg from docker hub: 
	
	singularity build afni.simg docker://afni/afni
	
	Afni seems to keep docker hub updated:
	
	singularity exec afni.simg afni --version 

3)	If using slurm, use gPPI.sbatch.sh to call gPPI.sh
	These should be in subject parent directory. 

4) 	For other schedulers, modify gPPI.sbach.sh

5)	I tested this in 3 segments then merged them into gPPI.sh. 
	Hopefully nothing broke when concatenatating the orginal scripts.
