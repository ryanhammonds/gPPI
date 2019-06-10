gPPI using AFNI

Supports multiple ROIs (one per analyses).
Appropropriate for block and event-related designs.

Generates:
a) Physiological Regressor
b) Interaction Regressor (for each task x physiological interaction).

Follows the generalized form described in McLaren et al., 2012:
A generalized form of context-dependent psychophysiological interactions (gPPI): a comparison to standard approaches.


1)  Install singularity on HPC

2)  Build afni.simg from docker hub:

    singularity build afni.simg docker://afni/afni

    Afni seems to keep docker hub updated:

    singularity exec afni.simg afni --version

3)  Run afni_proc.py

4)  Update gPPI.sh setup and 3dDeconvolve to reflect your design.

5)  If using slurm, use gPPI.sbatch.sh to call gPPI.sh
    These should be in parent directory (same level as subject's directories).

6)  For other schedulers, modify gPPI.sbatch.sh
