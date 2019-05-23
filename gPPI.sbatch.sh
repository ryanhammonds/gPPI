#!/bin/bash
#SBATCH --partition=debug
#SBATCH --cpus-per-task=1
#SBATCH --time=5:00:00
#SBATCH --array=0-89
#SBATCH -o array_%A_%a.out
#SBATCH -e array_%A_%a.err

# Set --array to number of subjects, index starting at 0.
# If subj > cpus available use --array=0-89%$max_cpus

# Run this from single subjects parent directory
subj_array=()
for subj in sub*; do
  subj_array+=($subj)
done

singularity exec \
--bind /path/to/PPI/parent/:/data/ \
/mnt/Filbey/Ryan/afni.simg \
/data/gPPI.sh ${subj_array[SLURM_ARRAY_TASK_ID]}
