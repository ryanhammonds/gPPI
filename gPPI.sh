#!/bin/bash

##########################################
## Author: Ryan Hammonds								##
## Wrote this using Gang Chen's example	##
##																			##
## gPPI with AFNI												##
## To be called with singularity+slurm	##
## Run afni_proc.py prior								##
##																			##
##########################################

##########################################
##   FIRST LEVEL 												##
##   Each Participant Directory Needs:	##
##	 1) pb05.*.scale+orig (or +tlrc)		##
##			(orig is recommended)						##
##	 2) stimuli subdirectory						##
##	 3) motion_demeaned.1D							##
##	 4) motion_*_censor.1D							##
##	 5) Anthing else used in basic GLM.	##
##      Such as nuisance regressor,etc.	##
##########################################

## SETUP ##
subj=$1

runs=(01 02) # two fMRI runs
run_len=480 # in seconds, not TRs

TR=2.5 # original TR
subTR=0.1 # in seconds, not TRs
subTR_inv=10 # 1/subTR (bash artithemtic doesn't like floats)
TRnup=$(($TR*$subTR_inv)) # TR / subTR
nt=$(($run_len*$subTR_inv)) # number of upsampled timepoints

space=tlrc # Change this if processing in native space
rois=(roi1+$space roi2+$space roi3+$space roi4+$space) # seed masks in space defined above
# These mask should be in a directory named "rois" in the subject parent directory

# Name below based on what is in your stimuli directories
stims=(Neg Neu Pos) # Stimuli Valence (Emotion)
tasks=(C I V) # Tasks (stroop): congru, incongru, viewing
# 9 total trial types (NegC, NegI, NegC, etc)

echo 'Preparing regressors...'

# Generate HRF
waver -dt $subTR -GAM -inline 1@1 > /data/GammaHR.1D
# Resample timing grid to 0.1s to create binary timing files.
for stim in ${stims[@]}; do
	for task in ${tasks[@]}; do
		timing_tool.py -timing /data/$subj/stimuli/AS_"$stim""$task".2.txt \
		-tr 0.1 -stim_dur 1.6 -run_len 480 -min_frac 0.5 -per_run \
		-timing_to_1D /data/$subj/stimuli/AS_"$stim""$task"_reSampled.1D
	done
done

# Deconvoluting and resampling of seed and interactions workflow
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

		# Synch to resampled TR grid. Argument 25 is from TR/0.1s when TR=2.5
		1dUpsample 25 /data/$subj/roi$x.run$run.detrend.1D\' > /data/$subj/roi$x.run$run.detrend.grid.1D

		# Deconvolve timeseries and estimate neural response
		3dTfitter -RHS /data/$subj/roi$x.run$run.detrend.grid.1D -FALTUNG /data/GammaHR.1D /data/$subj/roi$x.run$run.Neur 012 0
		1dtranspose /data/$subj/roi$x.run$run.Neur.1D /data/$subj/roi$x.run$run.Neur.trans.1D
	done

	# Split upsampled runs for each stimulus
	if [[ $run == 01 ]]; then
    for stim in ${stims[@]}; do
      for task in ${tasks[@]}; do
        cat /data/$subj/stimuli/AS_"$stim""$task"_reSampled.1D | head -n 1 >> /data/$subj/stimuli/AS_"$stim""$task"_reSampled_run01.1D
        1dtranspose /data/$subj/stimuli/AS_"$stim""$task"_reSampled_run01.1D /data/$subj/stimuli/AS_"$stim""$task"_reSampled_run01.trans.1D
			done
    done
  elif [[ $run == 02 ]]; then
    for stim in ${stims[@]}; do
      for task in ${tasks[@]}; do
        cat /data/$subj/stimuli/AS_"$stim""$task"_reSampled.1D | head -n 2 | tail -n 1 >> /data/$subj/stimuli/AS_"$stim""$task"_reSampled_run02.1D
        1dtranspose /data/$subj/stimuli/AS_"$stim""$task"_reSampled_run02.1D  /data/$subj/stimuli/AS_"$stim""$task"_reSampled_run02.trans.1D
      done
    done
  fi

	# Create interactions of from up sampled neural response x task regressors (1deval)
	# convolve these interatctions to HRF (waver) (per run/per roi)
	x=0
	for roi in ${rois[@]}; do
		(( x++ ))
    for stim in ${stims[@]}; do
      for task in ${tasks[@]}; do
				1deval \
				-a /data/$subj/roi$x.run$run.Neur.trans.1D \
				-b /data/$subj/stimuli/AS_"$stim""$task"_reSampled_run$run.trans.1D \
				-expr 'a*b' > /data/$subj/Inter/Inter.roi$x.run$run."$stim""$task".neu.1D

				waver \
				-FILE $subTR /data/GammaHR.1D \
				-input /data/$subj/Inter/Inter.roi$x.run$run."$stim""$task".neu.1D \
				-numout $nt > /data/$subj/Inter/Inter.roi$x.run$run."$stim""$task".reBOLD.1D
			done
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
    for task in ${tasks[@]}; do
      # Generate upsampled seeds that span runs
      cat /data/$subj/Inter/Inter.roi$x.run*."$stim""$task".reBOLD.1D \
      > /data/$subj/Inter/Inter.roi$x.rall."$stim""$task".reBOLD.1D
    done
  done
  # Generate upsampled neuro timeseries that span runs
  cat /data/$subj/roi$x.run*.Neur.trans.reBOLD.1D > /data/$subj/roi$x.rall.reBOLD.1D
done


# Downsample back to orginal TR grid
for run in ${runs[@]}; do
  x=0
  for roi in ${rois[@]}; do
    (( x++ ))
    for stim in ${stims[@]}; do
      for task in ${tasks[@]}; do
        # Downsample interactions
        1dcat /data/$subj/Inter/Inter.roi$x.run$run."$stim""$task".reBOLD.1D'{0..$('$TRnup')}' \
        > /data/$subj/Inter/Inter.roi$x.run$run."$stim""$task".PPIdown.1D
      done
    done

    # Downsample seed timeseries
    1dcat /data/$subj/roi$x.rall.reBOLD.1D'{0..$('$TRnup')}' \
    > /data/$subj/roi$x.rall.reBOLD.down.1D
  done
done

# catentate across runs: final PPI regressors
x=0
for roi in ${rois[@]}; do
  (( x++ ))
  for stim in ${stims[@]}; do
    for task in ${tasks[@]}; do
      cat /data/$subj/Inter/Inter.roi$x.run*."$stim""$task".PPIdown.1D \
      > /data/$subj/Inter/Inter.roi$x.rall."$stim""$task".PPI.1D
    done
  done
done


# Final First Level Products:
# Interaction regressors: /data/$subj/Inter/Inter.roi$x.rall."$stim""$task".PPI.1D
# Physiological regressors: /data/$subj/roi$x.rall.reBOLD.down.1D

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
	-stim_times 1 /data/$subj/stimuli/AS_PosC.2.txt GAM -stim_label 1 PosC \
	-stim_times 2 /data/$subj/stimuli/AS_PosI.2.txt GAM -stim_label 2 PosI \
	-stim_times 3 /data/$subj/stimuli/AS_PosV.2.txt GAM -stim_label 3 PosV \
	-stim_times 4 /data/$subj/stimuli/AS_NegC.2.txt GAM -stim_label 4 NegC \
	-stim_times 5 /data/$subj/stimuli/AS_NegI.2.txt GAM -stim_label 5 NegI \
	-stim_times 6 /data/$subj/stimuli/AS_NegV.2.txt GAM -stim_label 6 NegV \
	-stim_times 7 /data/$subj/stimuli/AS_NeuC.2.txt GAM -stim_label 7 NeuC \
	-stim_times 8 /data/$subj/stimuli/AS_NeuI.2.txt GAM -stim_label 8 NeuI \
	-stim_times 9 /data/$subj/stimuli/AS_NeuV.2.txt GAM -stim_label 9 NeuV \
	-stim_times 10 /data/$subj/stimuli/AS_Incorrect.2.txt GAM -stim_label 10 Incorrect \
	-stim_file 11 "/data/$subj/motion_demean.1D[0]" -stim_base 11 -stim_label 11 roll \
	-stim_file 12 "/data/$subj/motion_demean.1D[1]" -stim_base 12 -stim_label 12 pitch \
	-stim_file 13 "/data/$subj/motion_demean.1D[2]" -stim_base 13 -stim_label 13 yaw \
	-stim_file 14 "/data/$subj/motion_demean.1D[3]" -stim_base 14 -stim_label 14 dS \
	-stim_file 15 "/data/$subj/motion_demean.1D[4]" -stim_base 15 -stim_label 15 dL \
	-stim_file 16 "/data/$subj/motion_demean.1D[5]" -stim_base 16 -stim_label 16 dP \
	-stim_file 17 "/data/$subj/roi$roi.rall.reBOLD.down.1D" -stim_label 10 Seed_TS \
	-stim_file 18 "/data/$subj/Inter/Inter.roi$roi.rall.PosC.PPI.1D" -stim_label 18 InterPosC \
	-stim_file 19 "/data/$subj/Inter/Inter.roi$roi.rall.PosI.PPI.1D" -stim_label 19 InterPosI \
	-stim_file 20 "/data/$subj/Inter/Inter.roi$roi.rall.PosV.PPI.1D" -stim_label 20 InterPosV \
	-stim_file 21 "/data/$subj/Inter/Inter.roi$roi.rall.NegC.PPI.1D" -stim_label 21 InterNegC \
	-stim_file 22 "/data/$subj/Inter/Inter.roi$roi.rall.NegI.PPI.1D" -stim_label 22 InterNegI \
	-stim_file 23 "/data/$subj/Inter/Inter.roi$roi.rall.NegV.PPI.1D" -stim_label 23 InterNegV \
	-stim_file 24 "/data/$subj/Inter/Inter.roi$roi.rall.NeuC.PPI.1D" -stim_label 24 InterNeuC \
	-stim_file 25 "/data/$subj/Inter/Inter.roi$roi.rall.NeuI.PPI.1D" -stim_label 25 InterNeuI \
	-stim_file 26 "/data/$subj/Inter/Inter.roi$roi.rall.NeuV.PPI.1D" -stim_label 26 InterNeuV \
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
