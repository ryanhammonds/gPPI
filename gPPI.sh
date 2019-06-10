#!/bin/bash

##########################################
## Author: Ryan Hammonds                ##
## Wrote this using Gang Chen's example ##
##                                      ##
## gPPI with AFNI                       ##
## To be called with singularity+slurm  ##
## Run afni_proc.py prior               ##
##########################################

##########################################
##  FIRST LEVEL                         ##
##  Each Participant Directory Needs:   ##
##  1) pb05.*.scale+orig (or +tlrc)     ##
##     (orig is recommended)            ##
##  2) stimuli subdirectory             ##
##  3) motion_demeaned.1D               ##
##  4) motion_*_censor.1D               ##
##  5) Anthing else used in basic GLM.  ##
##     Such as nuisance regressors,etc. ##
##########################################

## SETUP #################################################################################

## Change 3dDeconvolve at end to reflect standard GLM! ##

subj=$1

runs=(01 02) # two fMRI runs
run_len=475 # in seconds, not TRs

TR=2.5 # original TR
subTR=0.1 # in seconds, not TRs
subTR_inv=10 # 1/subTR 
TRnup=25 # TR/subTR
nt=$(($run_len*$subTR_inv)) # number of upsampled timepoints

space=orig # Change to 'tlrc' if processing in native space
rois=(roi1+$space roi2+$space roi3+$space roi4+$space) # seed masks
# These mask should be in a directory named "rois" in the subject parent directory               

# Base task names based on stimuli directories
stims=(Neg Neu Pos) # Stimuli Valence (Emotion)                                   
###########################################################################################

echo 'Preparing regressors...'

# Generate HRF
waver -dt $subTR -GAM -inline 1@1 > /data/GammaHR.1D
# Resample timing grid to 0.1s to create binary timing files.
for stim in ${stims[@]}; do
  timing_tool.py -timing /data/$subj/stimuli/"$stim".txt \
  -tr $sub_tr -stim_dur 1.6 -run_len $run_len -min_frac 0.5 -per_run \
  -timing_to_1D /data/$subj/stimuli/"$stim"_reSampled.1D
done

# Deconvolution and resampling of seed and interactions regressors
for run in ${runs[@]}; do
  x=0
  for roi in ${rois[@]}; do
    (( x++ ))
    # Extract average ROI timeseries to one column
    3dmaskave \
    -mask /data/rois/$roi \
    -quiet /data/$subj/pb05.Preproc_RDOC_V2.r$run.scale+$space \
    > /data/$subj/roi$x.run$run.1D

    # Detrend timeseries
    3dDetrend -polort 2 -prefix /data/$subj/roi$x.run$run.detrend /data/$subj/roi$x.run$run.1D\'

    # Synch to resampled TR grid.
    1dUpsample $TRnup /data/$subj/roi$x.run$run.detrend.1D\' > /data/$subj/roi$x.run$run.detrend.grid.1D

    # Deconvolve timeseries and estimate neural response
    3dTfitter -RHS /data/$subj/roi$x.run$run.detrend.grid.1D -FALTUNG /data/GammaHR.1D /data/$subj/roi$x.run$run.Neur 012 0
    1dtranspose /data/$subj/roi$x.run$run.Neur.1D /data/$subj/roi$x.run$run.Neur.trans.1D
  done

  cat /data/$subj/stimuli/"$stim"_reSampled.1D | head -n $run | tail -n 1 >> /data/$subj/stimuli/"$stim"_reSampled_run$run.1D
  1dtranspose /data/$subj/stimuli/"$stim"_reSampled_run$run.1D /data/$subj/stimuli/"$stim"_reSampled_run$run.trans.1D
     
  # Create interactions of from up sampled neural response x task regressors (1deval)
  # convolve these interatctions to HRF (waver) (per run/per roi)
  x=0
  for roi in ${rois[@]}; do
    (( x++ ))
    for stim in ${stims[@]}; do
      1deval \
      -a /data/$subj/roi$x.run$run.Neur.trans.1D \
      -b /data/$subj/stimuli/"$stim"_reSampled_run$run.trans.1D \
      -expr 'a*b' > /data/$subj/Inter/Inter.roi$x.run$run."$stim".neu.1D

      waver \
      -FILE $subTR /data/GammaHR.1D \
      -input /data/$subj/Inter/Inter.roi$x.run$run."$stim".neu.1D \
      -numout $nt > /data/$subj/Inter/Inter.roi$x.run$run."$stim".reBOLD.1D
    done

    # Convolve neural estimate timeseries with HRF (per run, per ROI)
    waver \
    -FILE $subTR /data/GammaHR.1D \
    -input /data/$subj/roi$x.run$run.Neur.trans.1D \
    -numout $nt > /data/$subj/roi$x.run$run.Neur.trans.reBOLD.1D
  done
done

# Collapse (combine) across runs
x=0
for roi in ${rois[@]}; do
  (( x++ ))
  for stim in ${stims[@]}; do
    # Generate upsampled seeds that span runs
    cat /data/$subj/Inter/Inter.roi$x.run*."$stim".reBOLD.1D \
    > /data/$subj/Inter/Inter.roi$x.$stim.rall.reBOLD.1D   
    # Downsample interactions
    1dcat /data/$subj/Inter/Inter.roi$x.$stim.rall.reBOLD.1D'{0..$('$TRnup')}' \
    > /data/$subj/Inter/Inter.roi$x.$stim.rall.reBOLD.down.1D
  done

  # Merge neuro estimates
  cat /data/$subj/roi$x.run*.Neur.trans.reBOLD.1D > /data/$subj/roi$x.rall.reBOLD.1D
  # Downsample neuroestimates
  1dcat /data/$subj/roi$x.rall.reBOLD.1D'{0..$('$TRnup')}' \
  > /data/$subj/roi$x.rall.reBOLD.down.1D
done

# Final Preproc Products:
# 1) Interaction regressors: /data/$subj/Inter/Inter.roi$x.$stim.rall.reBOLD.down.1D
# 2) Physiological regressors: /data/$subj/roi$x.rall.reBOLD.down.1D

# Run single subject gPPI (just addded seed and PPI regressors to original GLM)
x=0
for roi in ${rois[@]}; do
  (( x++ ))
  if [[ ! -d /data/$subj/roi$x ]]; then
    mkdir /data/$subj/roi$x
  fi
  3dDeconvolve \
  -input /data/pb05."$subj".r*.scale+$space.HEAD \
  -censor /data/motion_"$subj"_censor.1D[0] \
  -polort 4 \
  -num_stimts 26 \
  -stim_times 1 /data/$subj/stimuli/PosC.txt GAM -stim_label 1 PosC \
  -stim_times 2 /data/$subj/stimuli/PosI.txt GAM -stim_label 2 PosI \
  -stim_times 3 /data/$subj/stimuli/PosV.txt GAM -stim_label 3 PosV \
  -stim_times 4 /data/$subj/stimuli/NegC.txt GAM -stim_label 4 NegC \
  -stim_times 5 /data/$subj/stimuli/NegI.txt GAM -stim_label 5 NegI \
  -stim_times 6 /data/$subj/stimuli/NegV.txt GAM -stim_label 6 NegV \
  -stim_times 7 /data/$subj/stimuli/NeuC.txt GAM -stim_label 7 NeuC \
  -stim_times 8 /data/$subj/stimuli/NeuI.txt GAM -stim_label 8 NeuI \
  -stim_times 9 /data/$subj/stimuli/NeuV.txt GAM -stim_label 9 NeuV \
  -stim_times 10 /data/$subj/stimuli/Incorrect.txt GAM -stim_label 10 Incorrect \
  -stim_file 11 "/data/$subj/motion_demean.1D[0]" -stim_base 11 -stim_label 11 roll \
  -stim_file 12 "/data/$subj/motion_demean.1D[1]" -stim_base 12 -stim_label 12 pitch \
  -stim_file 13 "/data/$subj/motion_demean.1D[2]" -stim_base 13 -stim_label 13 yaw \
  -stim_file 14 "/data/$subj/motion_demean.1D[3]" -stim_base 14 -stim_label 14 dS \
  -stim_file 15 "/data/$subj/motion_demean.1D[4]" -stim_base 15 -stim_label 15 dL \
  -stim_file 16 "/data/$subj/motion_demean.1D[5]" -stim_base 16 -stim_label 16 dP \
  -stim_file 17 "/data/$subj/roi$roi.rall.reBOLD.down.1D" -stim_label 10 Seed_TS \
  -stim_file 18 "/data/$subj/Inter/Inter.roi$roi.PosC.rall.PPI.1D" -stim_label 18 InterPosC \
  -stim_file 19 "/data/$subj/Inter/Inter.roi$roi.PosI.rall.PPI.1D" -stim_label 19 InterPosI \
  -stim_file 20 "/data/$subj/Inter/Inter.roi$roi.PosV.rall.PPI.1D" -stim_label 20 InterPosV \
  -stim_file 21 "/data/$subj/Inter/Inter.roi$roi.NegC.rall.PPI.1D" -stim_label 21 InterNegC \
  -stim_file 22 "/data/$subj/Inter/Inter.roi$roi.NegI.rall.PPI.1D" -stim_label 22 InterNegI \
  -stim_file 23 "/data/$subj/Inter/Inter.roi$roi.NegV.rall.PPI.1D" -stim_label 23 InterNegV \
  -stim_file 24 "/data/$subj/Inter/Inter.roi$roi.NeuC.rall.PPI.1D" -stim_label 24 InterNeuC \
  -stim_file 25 "/data/$subj/Inter/Inter.roi$roi.NeuI.rall.PPI.1D" -stim_label 25 InterNeuI \
  -stim_file 26 "/data/$subj/Inter/Inter.roi$roi.NeuV.rall.PPI.1D" -stim_label 26 InterNeuV \
  -fout \
  -tout \
  -rout\
  -x1D /data/$subj/roi$x/X.xmat.roi$x.1D \
  -xjpeg /data/$subj/roi$x/X.ximg.roi$x.jpg \
  -x1D_uncensored /data/$subj/roi$x/X.nocensor.xmat.roi$x.1D \
  -fitts /data/$subj/roi$x/fitts.roi$x \
  -errts /data/$subj/roi$x/errts.roi$x \
  -cbucket /data/$subj/roi$x/betas.roi$x \
  -bucket /data/$subj/roi$x/stats.roi$x
done

echo ''
echo '1st level gPPI processing complete.'
echo 'Use 3dttest++ or 3dANOVA for group level analysis.'
echo ''
